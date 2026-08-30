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

        let sourceHash = try fileHash(at: sourceURL)
        for content in existingContents {
            let existingURL = container.mediaURL(for: content)
            if fileManager.fileExists(atPath: existingURL.path),
               let existingHash = try? fileHash(at: existingURL),
               existingHash == sourceHash {
                throw HikariError.duplicateContent
            }
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
        let fileSize = try sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let id = UUID()
        let mediaRelativePath = "Media/\(id.uuidString).\(storageExtension)"
        let thumbnailRelativePath = "Thumbnails/\(id.uuidString).jpg"
        let destinationURL = container.rootURL.appendingPathComponent(mediaRelativePath)
        let temporaryURL = container.mediaDirectoryURL
            .appendingPathComponent(".\(id.uuidString).importing")

        do {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            let thumbnailURL = container.rootURL.appendingPathComponent(thumbnailRelativePath)
            let generatedThumbnail = try? await generateThumbnail(
                asset: asset,
                destinationURL: thumbnailURL
            )

            return LiveContent(
                id: id,
                title: sourceURL.deletingPathExtension().lastPathComponent,
                relativePath: mediaRelativePath,
                fileSize: Int64(fileSize),
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

    private func fileHash(at url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize()
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
