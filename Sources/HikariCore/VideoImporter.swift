import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public final class VideoImporter {
    private let container: SharedContainer
    private let fileManager: FileManager

    public init(
        container: SharedContainer,
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.fileManager = fileManager
    }

    public func importVideo(
        from sourceURL: URL,
        existingContents: [LiveContent]
    ) async throws -> LiveContent {
        guard let storageExtension = VideoFileSupport.storageFileExtension(
            for: sourceURL
        ) else {
            throw HikariError.unsupportedFile
        }

        var hashes = VideoHashIndex(container: container, contents: existingContents)
        defer { hashes.persistChanges() }
        let sourceStamp = try VideoHashIndex.FileStamp(at: sourceURL)
        let sourceHash = try Self.fileHash(at: sourceURL)
        if hashes.containsDuplicate(ofSize: sourceStamp.size, sha256: sourceHash, in: existingContents) {
            throw HikariError.duplicateContent
        }

        let asset = AVURLAsset(url: sourceURL)
        let isPlayable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard isPlayable, duration.isNumeric, duration.seconds > 0, let track = videoTracks.first else {
            throw HikariError.unreadableVideo
        }

        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displaySize = naturalSize.applying(transform)
        let formatDescriptions = try await track.load(.formatDescriptions)
        let codec = formatDescriptions.first.map {
            Self.fourCharacterCode(CMFormatDescriptionGetMediaSubType($0))
        }
        let id = UUID()
        let mediaRelativePath = "Media/\(id.uuidString).\(storageExtension)"
        let thumbnailRelativePath = "Thumbnails/\(id.uuidString).jpg"
        let destinationURL = container.rootURL.appendingPathComponent(mediaRelativePath)
        let temporaryURL = container.mediaDirectoryURL
            .appendingPathComponent(".\(id.uuidString).importing")

        do {
            try fileManager.copyItem(at: sourceURL.resolvingSymlinksInPath(), to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            let copyStamp = try VideoHashIndex.FileStamp(at: destinationURL)
            let copiedHash = try Self.fileHash(at: destinationURL)
            if (copyStamp.size != sourceStamp.size || copiedHash != sourceHash),
               hashes.containsDuplicate(ofSize: copyStamp.size, sha256: copiedHash, in: existingContents) {
                throw HikariError.duplicateContent
            }
            hashes.remember(copiedHash, for: id, stamp: copyStamp)
            let thumbnailURL = container.rootURL.appendingPathComponent(thumbnailRelativePath)
            let generatedThumbnail = try? await generateThumbnail(
                asset: asset,
                destinationURL: thumbnailURL
            )

            return LiveContent(
                id: id,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                relativePath: mediaRelativePath,
                fileSize: copyStamp.size,
                duration: duration.seconds,
                width: Int(abs(displaySize.width)),
                height: Int(abs(displaySize.height)),
                codec: codec,
                thumbnailRelativePath: generatedThumbnail == true ? thumbnailRelativePath : nil
            )
        } catch let error as HikariError {
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: destinationURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            try? fileManager.removeItem(at: destinationURL)
            throw HikariError.fileCopyFailed(error.localizedDescription)
        }
    }

    private func generateThumbnail(
        asset: AVAsset,
        destinationURL: URL
    ) async throws -> Bool {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        let image: CGImage
        if #available(macOS 15.0, *) {
            image = try await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            ).image
        } else {
            image = try generator.copyCGImage(
                at: CMTime(seconds: 0.1, preferredTimescale: 600),
                actualTime: nil
            )
        }
        guard
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            return false
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
        )
        return CGImageDestinationFinalize(destination)
    }

    fileprivate static func fileHash(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func fourCharacterCode(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(bytes: bytes, encoding: .macOSRoman)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }
}

struct VideoHashIndex {
    struct FileStamp: Codable, Equatable {
        let size: Int64
        let modified: Date
        let inode: UInt64

        init(at url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path)
            guard let size = attributes[.size] as? NSNumber,
                  let modified = attributes[.modificationDate] as? Date,
                  let inode = attributes[.systemFileNumber] as? NSNumber else {
                throw CocoaError(.fileReadUnknown)
            }
            self.size = size.int64Value
            self.modified = modified
            self.inode = inode.uint64Value
        }
    }

    private struct Entry: Codable {
        let stamp: FileStamp
        let sha256: String
    }

    private let container: SharedContainer
    private let url: URL
    private var entries: [String: Entry]
    private var dirty: Bool

    init(container: SharedContainer, contents: [LiveContent]) {
        self.container = container
        url = container.rootURL.appendingPathComponent("video-hashes.json")
        let data = try? Data(contentsOf: url)
        let saved = data.flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        let ids = Set(contents.map { $0.id.uuidString })
        entries = saved.filter { ids.contains($0.key) }
        dirty = entries.count != saved.count
    }

    mutating func containsDuplicate(
        ofSize size: Int64, sha256: String, in contents: [LiveContent],
        hashFile: (URL) throws -> String = VideoImporter.fileHash
    ) -> Bool {
        for item in contents {
            let media = container.mediaURL(for: item)
            guard let stamp = try? FileStamp(at: media), stamp.size == size else { continue }
            if entries[item.id.uuidString]?.stamp != stamp {
                guard let hash = try? hashFile(media) else { continue }
                remember(hash, for: item.id, stamp: stamp)
            }
            if entries[item.id.uuidString]?.sha256 == sha256 { return true }
        }
        return false
    }

    mutating func remember(_ hash: String, for id: UUID, stamp: FileStamp) {
        entries[id.uuidString] = Entry(stamp: stamp, sha256: hash)
        dirty = true
    }

    func persistChanges() {
        guard dirty, let data = try? JSONEncoder().encode(entries) else { return }
        // The cache is disposable. A write failure only costs a future rehash.
        try? data.write(to: url, options: .atomic)
    }
}
