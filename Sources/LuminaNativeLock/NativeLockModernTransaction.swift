import Darwin
import Foundation

/// The macOS 26 Aerial extension reads a per-user manifest and media store.
/// This transaction intentionally never touches the legacy root-owned catalog.
public struct NativeLockModernEnvironment: Sendable {
    public let wallpaperRootURL: URL
    public let manifestURL: URL
    public let mediaDirectoryURL: URL
    public let previewDirectoryURL: URL
    public let supportedOperatingSystemMajorVersions: Set<Int>
    public let operatingSystemMajorVersion: Int

    public init(
        wallpaperRootURL: URL,
        manifestURL: URL,
        mediaDirectoryURL: URL,
        previewDirectoryURL: URL,
        supportedOperatingSystemMajorVersions: Set<Int>,
        operatingSystemMajorVersion: Int
    ) {
        self.wallpaperRootURL = wallpaperRootURL
        self.manifestURL = manifestURL
        self.mediaDirectoryURL = mediaDirectoryURL
        self.previewDirectoryURL = previewDirectoryURL
        self.supportedOperatingSystemMajorVersions = supportedOperatingSystemMajorVersions
        self.operatingSystemMajorVersion = operatingSystemMajorVersion
    }

    public static var live: NativeLockModernEnvironment {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/com.apple.wallpaper",
                isDirectory: true
            )
        let aerials = root.appendingPathComponent("aerials", isDirectory: true)
        return NativeLockModernEnvironment(
            wallpaperRootURL: root,
            manifestURL: aerials
                .appendingPathComponent("manifest", isDirectory: true)
                .appendingPathComponent("entries.json"),
            mediaDirectoryURL: aerials.appendingPathComponent("videos", isDirectory: true),
            previewDirectoryURL: aerials.appendingPathComponent("thumbnails", isDirectory: true),
            supportedOperatingSystemMajorVersions: [26],
            operatingSystemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }
}

public struct NativeLockModernResult: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let assetID: UUID
    public let originalManifestSHA256: String
    public let manifestSHA256: String

    public init(
        transactionID: UUID,
        assetID: UUID,
        originalManifestSHA256: String,
        manifestSHA256: String
    ) {
        self.transactionID = transactionID
        self.assetID = assetID
        self.originalManifestSHA256 = originalManifestSHA256
        self.manifestSHA256 = manifestSHA256
    }
}

public final class NativeLockModernTransactionManager: @unchecked Sendable {
    /// ASCII `HIKARI`, distinct from any third-party Aerial category.
    public static let categoryID = "48494B41-5249-4000-8000-000000000001"
    public static let subcategoryID = "48494B41-5249-4000-8000-000000000002"

    private let environment: NativeLockModernEnvironment
    private let fileManager: FileManager

    public init(
        environment: NativeLockModernEnvironment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    public func apply(
        request: NativeLockRequest,
        sourceTransactionURL: URL
    ) throws -> NativeLockModernResult {
        try validateOperatingSystem()
        try validate(request)

        guard FileManager.default.fileExists(atPath: environment.manifestURL.path) else {
            throw NativeLockTransactionError.aerialCatalogMissing
        }
        let originalManifest = try Data(contentsOf: environment.manifestURL)
        let originalManifestSHA256 = NativeLockDigest.sha256(of: originalManifest)
        var manifest = try manifestDictionary(from: originalManifest)
        try validateManifest(&manifest, assetID: request.assetID.uuidString)

        let originalURL = sourceTransactionURL.appendingPathComponent(
            NativeLockPaths.originalModernManifestFilename
        )
        try writePrivate(originalManifest, to: originalURL)

        let mediaURL = self.mediaURL(for: request.assetID)
        let previewURL = self.previewURL(for: request.assetID)
        var copiedMedia = false
        var copiedPreview = false
        do {
            try fileManager.createDirectory(
                at: environment.mediaDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            try fileManager.createDirectory(
                at: environment.previewDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )
            guard !fileManager.fileExists(atPath: mediaURL.path),
                  !fileManager.fileExists(atPath: previewURL.path) else {
                throw NativeLockTransactionError.unsafeSystemPath(
                    "Native Lock destination already exists."
                )
            }

            let stagedMediaURL = sourceTransactionURL.appendingPathComponent(
                NativeLockPaths.stagedMediaFilename
            )
            let stagedPreviewURL = sourceTransactionURL.appendingPathComponent(
                NativeLockPaths.stagedPreviewFilename
            )
            try validateStagedFile(stagedMediaURL, expectedHash: request.mediaSHA256)
            try validateStagedFile(stagedPreviewURL, expectedHash: request.previewSHA256)
            try fileManager.copyItem(at: stagedMediaURL, to: mediaURL)
            copiedMedia = true
            try fileManager.copyItem(at: stagedPreviewURL, to: previewURL)
            copiedPreview = true
            try makeReadableByWallpaperService(mediaURL)
            try makeReadableByWallpaperService(previewURL)

            var assets = manifest["assets"] as! [[String: Any]]
            var categories = manifest["categories"] as! [[String: Any]]
            assets.append(assetRecord(request: request, mediaURL: mediaURL, previewURL: previewURL))
            categories.append(categoryRecord(previewURL: previewURL, assetID: request.assetID))
            manifest["assets"] = assets
            manifest["categories"] = categories
            let updatedManifest = try JSONSerialization.data(
                withJSONObject: manifest,
                options: [.sortedKeys]
            )

            // Do not overwrite a concurrent user-level catalog update.
            guard NativeLockDigest.sha256(of: try Data(contentsOf: environment.manifestURL))
                    == originalManifestSHA256 else {
                throw NativeLockTransactionError.systemManifestChanged
            }
            try writeShared(updatedManifest, to: environment.manifestURL)
            return NativeLockModernResult(
                transactionID: request.transactionID,
                assetID: request.assetID,
                originalManifestSHA256: originalManifestSHA256,
                manifestSHA256: NativeLockDigest.sha256(of: updatedManifest)
            )
        } catch {
            if copiedPreview { try? fileManager.removeItem(at: previewURL) }
            if copiedMedia { try? fileManager.removeItem(at: mediaURL) }
            throw error
        }
    }

    public func restore(
        request: NativeLockRequest,
        sourceTransactionURL: URL,
        originalManifestSHA256: String,
        appliedManifestSHA256: String?
    ) throws {
        try validateOperatingSystem()
        try validate(request)
        guard NativeLockDigest.isValidSHA256(originalManifestSHA256) else {
            throw NativeLockTransactionError.invalidHash
        }
        let originalURL = sourceTransactionURL.appendingPathComponent(
            NativeLockPaths.originalModernManifestFilename
        )
        let original = try Data(contentsOf: originalURL)
        guard NativeLockDigest.sha256(of: original) == originalManifestSHA256 else {
            throw NativeLockTransactionError.invalidHash
        }
        let current = try Data(contentsOf: environment.manifestURL)
        let restored: Data
        if let appliedManifestSHA256,
           NativeLockDigest.sha256(of: current) == appliedManifestSHA256 {
            restored = original
        } else {
            var manifest = try manifestDictionary(from: current)
            guard var assets = manifest["assets"] as? [[String: Any]],
                  var categories = manifest["categories"] as? [[String: Any]] else {
                throw NativeLockTransactionError.invalidWallpaperStore
            }
            assets.removeAll { $0["id"] as? String == request.assetID.uuidString }
            // A manifest that no longer matches our applied hash was changed
            // by another process. Remove only this transaction's asset, and
            // retain the shared Hikari category while another Hikari asset
            // still references it. Removing the category in that case would
            // orphan an independently managed video.
            let hasOtherHikariAsset = assets.contains { asset in
                let categories = asset["categories"] as? [String] ?? []
                let subcategories = asset["subcategories"] as? [String] ?? []
                return categories.contains(Self.categoryID)
                    || subcategories.contains(Self.subcategoryID)
            }
            if !hasOtherHikariAsset {
                categories.removeAll { category in
                    let identifier = category["id"] as? String
                    return identifier == Self.categoryID
                        || identifier == Self.subcategoryID
                }
            }
            manifest["assets"] = assets
            manifest["categories"] = categories
            restored = try JSONSerialization.data(
                withJSONObject: manifest,
                options: [.sortedKeys]
            )
        }
        try writeShared(restored, to: environment.manifestURL)
        try removeOwnedFile(
            mediaURL(for: request.assetID),
            expectedHash: request.mediaSHA256
        )
        try removeOwnedFile(
            previewURL(for: request.assetID),
            expectedHash: request.previewSHA256
        )
    }

    private func validateOperatingSystem() throws {
        guard environment.supportedOperatingSystemMajorVersions.contains(
            environment.operatingSystemMajorVersion
        ) else {
            throw NativeLockTransactionError.unsupportedOperatingSystem(
                environment.operatingSystemMajorVersion
            )
        }
    }

    private func validate(_ request: NativeLockRequest) throws {
        guard request.schemaVersion == NativeLockRequest.schemaVersion,
              NativeLockDigest.isValidSHA256(request.mediaSHA256),
              NativeLockDigest.isValidSHA256(request.previewSHA256) else {
            throw NativeLockTransactionError.unsupportedSchema
        }
    }

    private func validateManifest(
        _ manifest: inout [String: Any],
        assetID: String
    ) throws {
        guard manifest["version"] as? Int == 1,
              let assets = manifest["assets"] as? [[String: Any]],
              let categories = manifest["categories"] as? [[String: Any]],
              !assets.contains(where: { $0["id"] as? String == assetID }),
              !categories.contains(where: {
                  let identifier = $0["id"] as? String
                  return identifier == Self.categoryID || identifier == Self.subcategoryID
              }) else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
    }

    private func manifestDictionary(from data: Data) throws -> [String: Any] {
        guard let manifest = try JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        return manifest
    }

    private func assetRecord(
        request: NativeLockRequest,
        mediaURL: URL,
        previewURL: URL
    ) -> [String: Any] {
        let assetID = request.assetID.uuidString
        let shotID = "HIKARI_" + assetID.replacingOccurrences(of: "-", with: "_")
        return [
            "accessibilityLabel": request.title,
            "categories": [Self.categoryID],
            "id": assetID,
            "includeInShuffle": true,
            "localizedNameKey": request.title,
            "pointsOfInterest": ["0": shotID + "_0"],
            "preferredOrder": 0,
            "previewImage": previewURL.absoluteString,
            "shotID": shotID,
            "showInTopLevel": true,
            "subcategories": [Self.subcategoryID],
            "url-4K-SDR-240FPS": mediaURL.absoluteString
        ]
    }

    private func categoryRecord(previewURL: URL, assetID: UUID) -> [String: Any] {
        [
            "id": Self.categoryID,
            "localizedDescriptionKey": "Hikari custom Lock Screen videos",
            "localizedNameKey": "Hikari",
            "preferredOrder": 0,
            "previewImage": previewURL.absoluteString,
            "representativeAssetID": assetID.uuidString,
            "subcategories": [[
                "id": Self.subcategoryID,
                "localizedDescriptionKey": "Hikari custom Lock Screen videos",
                "localizedNameKey": "Hikari",
                "preferredOrder": 0,
                "previewImage": previewURL.absoluteString,
                "representativeAssetID": assetID.uuidString
            ]]
        ]
    }

    private func mediaURL(for assetID: UUID) -> URL {
        environment.mediaDirectoryURL.appendingPathComponent(assetID.uuidString + ".mov")
    }

    private func previewURL(for assetID: UUID) -> URL {
        environment.previewDirectoryURL.appendingPathComponent(assetID.uuidString + ".png")
    }

    private func validateStagedFile(_ url: URL, expectedHash: String) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1,
              try NativeLockDigest.sha256(of: url) == expectedHash else {
            throw NativeLockTransactionError.sourceHashMismatch
        }
    }

    private func removeOwnedFile(_ url: URL, expectedHash: String) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard try NativeLockDigest.sha256(of: url) == expectedHash else { return }
        try fileManager.removeItem(at: url)
        try synchronizeParent(of: url)
    }

    private func makeReadableByWallpaperService(_ url: URL) throws {
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: url.path
        )
        try synchronizeFileAndParent(url)
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try synchronizeFileAndParent(url)
    }

    private func writeShared(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try synchronizeFileAndParent(url)
    }

    private func synchronizeFileAndParent(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try synchronizeParent(of: url)
    }

    private func synchronizeParent(of url: URL) throws {
        let descriptor = open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
