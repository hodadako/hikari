import CryptoKit
import Darwin
import Foundation

public struct NativeLockSystemEnvironment: Sendable {
    public let systemSupportRootURL: URL
    public let manifestURL: URL
    public let mediaDirectoryURL: URL
    public let previewDirectoryURL: URL
    public let cacheURLs: [URL]
    public let supportedOperatingSystemMajorVersions: Set<Int>
    public let operatingSystemMajorVersion: Int
    public let enforceRootOwnership: Bool

    public init(
        systemSupportRootURL: URL,
        manifestURL: URL,
        mediaDirectoryURL: URL,
        previewDirectoryURL: URL,
        cacheURLs: [URL],
        supportedOperatingSystemMajorVersions: Set<Int>,
        operatingSystemMajorVersion: Int,
        enforceRootOwnership: Bool
    ) {
        self.systemSupportRootURL = systemSupportRootURL
        self.manifestURL = manifestURL
        self.mediaDirectoryURL = mediaDirectoryURL
        self.previewDirectoryURL = previewDirectoryURL
        self.cacheURLs = cacheURLs
        self.supportedOperatingSystemMajorVersions = supportedOperatingSystemMajorVersions
        self.operatingSystemMajorVersion = operatingSystemMajorVersion
        self.enforceRootOwnership = enforceRootOwnership
    }

    public static var live: NativeLockSystemEnvironment {
        let idleAssetsRoot = NativeLockPaths.idleAssetsRoot
        return NativeLockSystemEnvironment(
            systemSupportRootURL: NativeLockPaths.systemSupportRoot,
            manifestURL: idleAssetsRoot
                .appendingPathComponent("Customer", isDirectory: true)
                .appendingPathComponent("entries.json"),
            mediaDirectoryURL: idleAssetsRoot
                .appendingPathComponent("Customer", isDirectory: true)
                .appendingPathComponent("4KSDR240FPS", isDirectory: true),
            previewDirectoryURL: idleAssetsRoot
                .appendingPathComponent("snapshots", isDirectory: true),
            cacheURLs: [
                idleAssetsRoot.appendingPathComponent("Aerial.sqlite"),
                idleAssetsRoot.appendingPathComponent("Aerial.sqlite-shm"),
                idleAssetsRoot.appendingPathComponent("Aerial.sqlite-wal")
            ],
            // The observed schema is intentionally pinned to macOS 15. A new
            // major release must be inspected before writes are enabled.
            supportedOperatingSystemMajorVersions: [15],
            operatingSystemMajorVersion: ProcessInfo.processInfo
                .operatingSystemVersion.majorVersion,
            enforceRootOwnership: true
        )
    }
}

public struct NativeLockSystemResult: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let assetID: UUID
    public let manifestSHA256: String
    public let operation: String

    public init(
        transactionID: UUID,
        assetID: UUID,
        manifestSHA256: String,
        operation: String
    ) {
        self.transactionID = transactionID
        self.assetID = assetID
        self.manifestSHA256 = manifestSHA256
        self.operation = operation
    }
}

public final class NativeLockSystemTransactionManager: @unchecked Sendable {
    public static let categoryID = "4C554D49-4E41-4000-8000-000000000001"
    public static let subcategoryID = "4C554D49-4E41-4000-8000-000000000002"

    private let environment: NativeLockSystemEnvironment
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        environment: NativeLockSystemEnvironment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
        self.encoder = JSONEncoder.nativeSystemEncoder
        self.decoder = JSONDecoder.nativeSystemDecoder
    }

    public func apply(
        request: NativeLockRequest,
        sourceTransactionURL: URL
    ) throws -> NativeLockSystemResult {
        try validate(request)
        try validateOperatingSystem()
        try prepareAndHardenSystemDirectories()
        guard !fileManager.fileExists(atPath: activeStateURL.path),
              try unfinishedSystemJournal() == nil else {
            throw NativeLockTransactionError.activeTransactionExists
        }

        let transactionRoot = systemTransactionURL(for: request.transactionID)
        try fileManager.createDirectory(
            at: transactionRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let originalManifestData = try validatedManifestData()
        guard try !manifestContainsLuminaEntries(
            assetID: request.assetID,
            in: originalManifestData
        ) else {
            throw NativeLockTransactionError.systemManifestChanged
        }
        let originalManifestHash = NativeLockDigest.sha256(of: originalManifestData)
        let originalManifestURL = transactionRoot.appendingPathComponent(
            "entries.original.json"
        )
        try originalManifestData.write(to: originalManifestURL, options: .atomic)
        try setRootOnlyPermissions(originalManifestURL)
        try synchronizeFileAndParent(originalManifestURL)
        var systemJournal = NativeLockSystemJournal(
            transactionID: request.transactionID,
            assetID: request.assetID,
            phase: .prepared,
            originalManifestSHA256: originalManifestHash,
            appliedManifestSHA256: nil,
            mediaSHA256: request.mediaSHA256,
            previewSHA256: request.previewSHA256,
            createdAt: Date(),
            updatedAt: Date()
        )
        try write(systemJournal, to: systemJournalURL(for: request.transactionID))

        let mediaURL = systemMediaURL(for: request.assetID)
        let previewURL = systemPreviewURL(for: request.assetID)
        let sourceMediaURL = sourceTransactionURL.appendingPathComponent(
            NativeLockPaths.stagedMediaFilename
        )
        let sourcePreviewURL = sourceTransactionURL.appendingPathComponent(
            NativeLockPaths.stagedPreviewFilename
        )
        var installedMedia = false
        var installedPreview = false
        var appliedManifestHashForRollback: String?
        do {
            guard !fileManager.fileExists(atPath: mediaURL.path),
                  !fileManager.fileExists(atPath: previewURL.path) else {
                throw NativeLockTransactionError.unsafeSystemPath(
                    "Native Lock destination already exists."
                )
            }
            try copyValidatedUserFile(
                from: sourceMediaURL,
                to: mediaURL,
                expectedOwner: uid_t(request.userID),
                expectedHash: request.mediaSHA256
            )
            installedMedia = true
            try copyValidatedUserFile(
                from: sourcePreviewURL,
                to: previewURL,
                expectedOwner: uid_t(request.userID),
                expectedHash: request.previewSHA256
            )
            installedPreview = true

            let appliedManifestData = try manifestByAdding(
                request: request,
                mediaURL: mediaURL,
                previewURL: previewURL,
                to: originalManifestData
            )
            let appliedManifestHash = NativeLockDigest.sha256(
                of: appliedManifestData
            )
            appliedManifestHashForRollback = appliedManifestHash
            try writeManifest(appliedManifestData)
            systemJournal.phase = .manifestApplied
            systemJournal.appliedManifestSHA256 = appliedManifestHash
            systemJournal.updatedAt = Date()
            try write(
                systemJournal,
                to: systemJournalURL(for: request.transactionID)
            )

            try backupAndInvalidateCaches(transactionRoot: transactionRoot)
            try write(
                NativeLockSystemActiveState(
                    transactionID: request.transactionID,
                    assetID: request.assetID
                ),
                to: activeStateURL
            )
            systemJournal.phase = .active
            systemJournal.updatedAt = Date()
            try write(
                systemJournal,
                to: systemJournalURL(for: request.transactionID)
            )
            return NativeLockSystemResult(
                transactionID: request.transactionID,
                assetID: request.assetID,
                manifestSHA256: appliedManifestHash,
                operation: "apply"
            )
        } catch {
            if let appliedManifestHashForRollback {
                try? rollbackAppliedManifest(
                    assetID: request.assetID,
                    originalData: originalManifestData,
                    appliedHash: appliedManifestHashForRollback
                )
            }
            if installedMedia {
                try? removeOwnedAsset(at: mediaURL, expectedHash: request.mediaSHA256)
            }
            if installedPreview {
                try? removeOwnedAsset(at: previewURL, expectedHash: request.previewSHA256)
            }
            try? restoreInvalidatedCaches(transactionRoot: transactionRoot)
            try? fileManager.removeItem(at: activeStateURL)
            systemJournal.phase = .restored
            systemJournal.updatedAt = Date()
            try? write(
                systemJournal,
                to: systemJournalURL(for: request.transactionID)
            )
            throw error
        }
    }

    public func restore(
        request: NativeLockRequest
    ) throws -> NativeLockSystemResult {
        try validate(request)
        try validateOperatingSystem()
        try prepareAndHardenSystemDirectories()
        let journalURL = systemJournalURL(for: request.transactionID)
        guard fileManager.fileExists(atPath: journalURL.path) else {
            let currentManifest = try validatedManifestData()
            guard try !manifestContainsLuminaEntries(
                assetID: request.assetID,
                in: currentManifest
            ) else {
                throw NativeLockTransactionError.systemManifestChanged
            }
            guard !fileManager.fileExists(
                atPath: systemMediaURL(for: request.assetID).path
            ), !fileManager.fileExists(
                atPath: systemPreviewURL(for: request.assetID).path
            ) else {
                throw NativeLockTransactionError.systemAssetChanged
            }
            return NativeLockSystemResult(
                transactionID: request.transactionID,
                assetID: request.assetID,
                manifestSHA256: NativeLockDigest.sha256(of: currentManifest),
                operation: "restore-noop"
            )
        }
        var journal: NativeLockSystemJournal = try read(
            NativeLockSystemJournal.self,
            from: journalURL
        )
        guard journal.transactionID == request.transactionID,
              journal.assetID == request.assetID else {
            throw NativeLockTransactionError.transactionMismatch
        }
        if fileManager.fileExists(atPath: activeStateURL.path) {
            let active: NativeLockSystemActiveState = try read(
                NativeLockSystemActiveState.self,
                from: activeStateURL
            )
            guard active.transactionID == request.transactionID,
                  active.assetID == request.assetID else {
                throw NativeLockTransactionError.transactionMismatch
            }
        }

        let currentManifest = try validatedManifestData()
        let currentHash = NativeLockDigest.sha256(of: currentManifest)
        let restoredManifest: Data
        if let appliedManifestSHA256 = journal.appliedManifestSHA256,
           currentHash == appliedManifestSHA256 {
            let originalURL = systemTransactionURL(for: request.transactionID)
                .appendingPathComponent("entries.original.json")
            let originalData = try Data(contentsOf: originalURL)
            guard NativeLockDigest.sha256(of: originalData)
                    == journal.originalManifestSHA256 else {
                throw NativeLockTransactionError.systemManifestChanged
            }
            restoredManifest = originalData
        } else {
            restoredManifest = try manifestByRemovingLuminaEntries(
                assetID: request.assetID,
                from: currentManifest
            )
        }

        let mediaURL = systemMediaURL(for: request.assetID)
        let previewURL = systemPreviewURL(for: request.assetID)
        try validateOwnedAsset(at: mediaURL, expectedHash: journal.mediaSHA256)
        try validateOwnedAsset(at: previewURL, expectedHash: journal.previewSHA256)
        try writeManifest(restoredManifest)
        try removeOwnedAsset(at: mediaURL, expectedHash: journal.mediaSHA256)
        try removeOwnedAsset(at: previewURL, expectedHash: journal.previewSHA256)
        try backupAndInvalidateCaches(
            transactionRoot: systemTransactionURL(for: request.transactionID),
            directoryName: "cache-before-restore"
        )
        if fileManager.fileExists(atPath: activeStateURL.path) {
            try fileManager.removeItem(at: activeStateURL)
        }
        journal.phase = .restored
        journal.updatedAt = Date()
        try write(journal, to: journalURL)

        return NativeLockSystemResult(
            transactionID: request.transactionID,
            assetID: request.assetID,
            manifestSHA256: NativeLockDigest.sha256(of: restoredManifest),
            operation: "restore"
        )
    }

    public func activeTransaction() throws -> (transactionID: UUID, assetID: UUID)? {
        guard fileManager.fileExists(atPath: activeStateURL.path) else { return nil }
        let active: NativeLockSystemActiveState = try read(
            NativeLockSystemActiveState.self,
            from: activeStateURL
        )
        return (active.transactionID, active.assetID)
    }

    private var activeStateURL: URL {
        environment.systemSupportRootURL.appendingPathComponent("active.json")
    }

    private func systemTransactionURL(for transactionID: UUID) -> URL {
        environment.systemSupportRootURL
            .appendingPathComponent("Transactions", isDirectory: true)
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
    }

    private func systemJournalURL(for transactionID: UUID) -> URL {
        systemTransactionURL(for: transactionID)
            .appendingPathComponent("system-journal.json")
    }

    private func unfinishedSystemJournal() throws -> NativeLockSystemJournal? {
        let transactionsURL = environment.systemSupportRootURL
            .appendingPathComponent("Transactions", isDirectory: true)
        guard let entries = try? fileManager.contentsOfDirectory(
            at: transactionsURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        for entry in entries {
            let journalURL = entry.appendingPathComponent("system-journal.json")
            guard fileManager.fileExists(atPath: journalURL.path) else { continue }
            let journal: NativeLockSystemJournal = try read(
                NativeLockSystemJournal.self,
                from: journalURL
            )
            if journal.phase != .restored {
                return journal
            }
        }
        return nil
    }

    private func systemMediaURL(for assetID: UUID) -> URL {
        environment.mediaDirectoryURL
            .appendingPathComponent("\(assetID.uuidString).mov")
    }

    private func systemPreviewURL(for assetID: UUID) -> URL {
        environment.previewDirectoryURL
            .appendingPathComponent("asset-preview-\(assetID.uuidString).jpg")
    }

    private func validate(_ request: NativeLockRequest) throws {
        guard request.schemaVersion == NativeLockRequest.schemaVersion else {
            throw NativeLockTransactionError.unsupportedSchema
        }
        guard NativeLockDigest.isValidSHA256(request.mediaSHA256),
              NativeLockDigest.isValidSHA256(request.previewSHA256) else {
            throw NativeLockTransactionError.invalidHash
        }
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

    private func prepareAndHardenSystemDirectories() throws {
        try fileManager.createDirectory(
            at: environment.systemSupportRootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try hardenDirectory(environment.systemSupportRootURL, permissions: 0o700)
        try hardenDirectory(environment.manifestURL.deletingLastPathComponent())
        try hardenDirectory(environment.mediaDirectoryURL)
        try hardenDirectory(environment.previewDirectoryURL)
        try hardenRegularFile(environment.manifestURL)
    }

    private func hardenDirectory(
        _ url: URL,
        permissions: mode_t = 0o755
    ) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & S_IFMT != S_IFLNK else {
            throw NativeLockTransactionError.unsafeSystemPath(url.path)
        }
        if environment.enforceRootOwnership, info.st_uid != 0 {
            throw NativeLockTransactionError.unsafeSystemPath(url.path)
        }
        guard chmod(url.path, permissions) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
    }

    private func hardenRegularFile(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1 else {
            throw NativeLockTransactionError.unsafeSystemPath(url.path)
        }
        if environment.enforceRootOwnership, info.st_uid != 0 {
            throw NativeLockTransactionError.unsafeSystemPath(url.path)
        }
        guard chmod(url.path, 0o644) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
    }

    private func validatedManifestData() throws -> Data {
        let data = try Data(contentsOf: environment.manifestURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["version"] as? NSNumber)?.intValue == 1,
              root["assets"] is [[String: Any]],
              root["categories"] is [[String: Any]] else {
            throw NativeLockTransactionError.unsupportedSchema
        }
        return data
    }

    private func manifestByAdding(
        request: NativeLockRequest,
        mediaURL: URL,
        previewURL: URL,
        to data: Data
    ) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var assets = root["assets"] as? [[String: Any]],
              var categories = root["categories"] as? [[String: Any]] else {
            throw NativeLockTransactionError.unsupportedSchema
        }
        assets.removeAll { asset in
            asset["id"] as? String == request.assetID.uuidString
                || (asset["categories"] as? [String])?.contains(Self.categoryID) == true
        }
        categories.removeAll { category in
            category["id"] as? String == Self.categoryID
        }

        let assetID = request.assetID.uuidString
        let shotID = "LUMINA_\(assetID.replacingOccurrences(of: "-", with: "_"))"
        let asset: [String: Any] = [
            "accessibilityLabel": request.title,
            "categories": [Self.categoryID],
            "shotID": shotID,
            "id": assetID,
            "includeInShuffle": true,
            "showInTopLevel": true,
            "pointsOfInterest": ["0": "\(shotID)_0"],
            "localizedNameKey": request.title,
            "preferredOrder": 0,
            "subcategories": [Self.subcategoryID],
            "previewImage": previewURL.absoluteString,
            "url-4K-SDR-240FPS": mediaURL.absoluteString
        ]
        let subcategory: [String: Any] = [
            "id": Self.subcategoryID,
            "previewImage": previewURL.absoluteString,
            "localizedNameKey": "Lumina",
            "preferredOrder": 0,
            "representativeAssetID": assetID,
            "localizedDescriptionKey": "Local videos managed by Lumina Native Local"
        ]
        let category: [String: Any] = [
            "subcategories": [subcategory],
            "id": Self.categoryID,
            "previewImage": previewURL.absoluteString,
            "localizedNameKey": "Lumina",
            "preferredOrder": 0,
            "localizedDescriptionKey": "Local videos managed by Lumina Native Local",
            "representativeAssetID": assetID
        ]
        assets.append(asset)
        categories.append(category)
        root["assets"] = assets
        root["categories"] = categories
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func manifestByRemovingLuminaEntries(
        assetID: UUID,
        from data: Data
    ) throws -> Data {
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var assets = root["assets"] as? [[String: Any]],
              var categories = root["categories"] as? [[String: Any]] else {
            throw NativeLockTransactionError.unsupportedSchema
        }
        assets.removeAll { asset in
            asset["id"] as? String == assetID.uuidString
                || (asset["categories"] as? [String])?.contains(Self.categoryID) == true
        }
        categories.removeAll { category in
            category["id"] as? String == Self.categoryID
        }
        root["assets"] = assets
        root["categories"] = categories
        return try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func manifestContainsLuminaEntries(
        assetID: UUID,
        in data: Data
    ) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = root["assets"] as? [[String: Any]],
              let categories = root["categories"] as? [[String: Any]] else {
            throw NativeLockTransactionError.unsupportedSchema
        }
        return assets.contains {
            $0["id"] as? String == assetID.uuidString
                || ($0["categories"] as? [String])?.contains(Self.categoryID) == true
        } || categories.contains { $0["id"] as? String == Self.categoryID }
    }

    private func rollbackAppliedManifest(
        assetID: UUID,
        originalData: Data,
        appliedHash: String
    ) throws {
        let current = try validatedManifestData()
        let rollbackData: Data
        if NativeLockDigest.sha256(of: current) == appliedHash {
            rollbackData = originalData
        } else {
            rollbackData = try manifestByRemovingLuminaEntries(
                assetID: assetID,
                from: current
            )
        }
        try writeManifest(rollbackData)
    }

    private func writeManifest(_ data: Data) throws {
        let temporaryURL = environment.manifestURL.deletingLastPathComponent()
            .appendingPathComponent(".entries.\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .withoutOverwriting)
        try setPublicReadOnlyPermissions(temporaryURL)
        if rename(temporaryURL.path, environment.manifestURL.path) != 0 {
            let savedError = errno
            try? fileManager.removeItem(at: temporaryURL)
            throw POSIXError(POSIXErrorCode(rawValue: savedError) ?? .EIO)
        }
        try synchronizeFileAndParent(environment.manifestURL)
    }

    private func copyValidatedUserFile(
        from sourceURL: URL,
        to destinationURL: URL,
        expectedOwner: uid_t,
        expectedHash: String
    ) throws {
        var sourceInfo = stat()
        guard lstat(sourceURL.path, &sourceInfo) == 0 else {
            throw NativeLockTransactionError.sourceMissing
        }
        guard sourceInfo.st_mode & S_IFMT == S_IFREG,
              sourceInfo.st_nlink == 1 else {
            throw NativeLockTransactionError.sourceNotRegularFile
        }
        guard !environment.enforceRootOwnership || sourceInfo.st_uid == expectedOwner else {
            throw NativeLockTransactionError.sourceOwnerMismatch
        }

        let sourceDescriptor = open(sourceURL.path, O_RDONLY | O_NOFOLLOW)
        guard sourceDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        defer { close(sourceDescriptor) }
        guard fstat(sourceDescriptor, &sourceInfo) == 0,
              sourceInfo.st_mode & S_IFMT == S_IFREG,
              sourceInfo.st_nlink == 1 else {
            throw NativeLockTransactionError.sourceNotRegularFile
        }
        guard !environment.enforceRootOwnership || sourceInfo.st_uid == expectedOwner else {
            throw NativeLockTransactionError.sourceOwnerMismatch
        }

        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp")
        let destinationDescriptor = open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            0o600
        )
        guard destinationDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        var shouldRemoveTemporary = true
        defer {
            close(destinationDescriptor)
            if shouldRemoveTemporary {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let readCount = Darwin.read(sourceDescriptor, &buffer, buffer.count)
            guard readCount >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if readCount == 0 { break }
            hasher.update(data: Data(buffer[0..<readCount]))
            var written = 0
            while written < readCount {
                let writeCount = buffer.withUnsafeBytes { rawBuffer in
                    Darwin.write(
                        destinationDescriptor,
                        rawBuffer.baseAddress!.advanced(by: written),
                        readCount - written
                    )
                }
                guard writeCount > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                written += writeCount
            }
        }
        let copiedHash = hasher.finalize().map {
            String(format: "%02x", $0)
        }.joined()
        guard copiedHash == expectedHash else {
            throw NativeLockTransactionError.sourceHashMismatch
        }
        guard fsync(destinationDescriptor) == 0,
              fchmod(destinationDescriptor, 0o644) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        if environment.enforceRootOwnership {
            guard fchown(destinationDescriptor, 0, 80) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
        }
        if rename(temporaryURL.path, destinationURL.path) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        shouldRemoveTemporary = false
        try synchronizeParent(of: destinationURL)
    }

    private func removeOwnedAsset(at url: URL, expectedHash: String) throws {
        try validateOwnedAsset(at: url, expectedHash: expectedHash)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func validateOwnedAsset(at url: URL, expectedHash: String) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1 else {
            throw NativeLockTransactionError.systemAssetChanged
        }
        guard try NativeLockDigest.sha256(of: url) == expectedHash else {
            throw NativeLockTransactionError.systemAssetChanged
        }
    }

    private func backupAndInvalidateCaches(
        transactionRoot: URL,
        directoryName: String = "cache-before-apply"
    ) throws {
        let backupDirectory = transactionRoot.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        for cacheURL in environment.cacheURLs where fileManager.fileExists(
            atPath: cacheURL.path
        ) {
            var info = stat()
            guard lstat(cacheURL.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG,
                  info.st_nlink == 1,
                  !environment.enforceRootOwnership || info.st_uid == 0 else {
                throw NativeLockTransactionError.unsafeSystemPath(cacheURL.path)
            }
            let backupURL = backupDirectory.appendingPathComponent(
                cacheURL.lastPathComponent
            )
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: cacheURL, to: backupURL)
        }
    }

    private func restoreInvalidatedCaches(transactionRoot: URL) throws {
        let backupDirectory = transactionRoot.appendingPathComponent(
            "cache-before-apply",
            isDirectory: true
        )
        guard let backups = try? fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let liveByName = Dictionary(
            uniqueKeysWithValues: environment.cacheURLs.map {
                ($0.lastPathComponent, $0)
            }
        )
        for backup in backups {
            guard let live = liveByName[backup.lastPathComponent],
                  !fileManager.fileExists(atPath: live.path) else {
                continue
            }
            try fileManager.moveItem(at: backup, to: live)
        }
    }

    private func setRootOnlyPermissions(_ url: URL) throws {
        guard chmod(url.path, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        if environment.enforceRootOwnership {
            guard chown(url.path, 0, 0) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
        }
    }

    private func setPublicReadOnlyPermissions(_ url: URL) throws {
        guard chmod(url.path, 0o644) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES)
        }
        if environment.enforceRootOwnership {
            guard chown(url.path, 0, 80) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
        }
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try encoder.encode(value).write(to: url, options: .atomic)
        try setRootOnlyPermissions(url)
        try synchronizeFileAndParent(url)
    }

    private func read<Value: Decodable>(
        _ type: Value.Type,
        from url: URL
    ) throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            throw NativeLockTransactionError.transactionNotFound
        }
        return try decoder.decode(type, from: Data(contentsOf: url))
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

private enum NativeLockSystemPhase: String, Codable {
    case prepared
    case manifestApplied
    case active
    case restored
}

private struct NativeLockSystemJournal: Codable {
    let transactionID: UUID
    let assetID: UUID
    var phase: NativeLockSystemPhase
    let originalManifestSHA256: String
    var appliedManifestSHA256: String?
    let mediaSHA256: String
    let previewSHA256: String
    let createdAt: Date
    var updatedAt: Date
}

private struct NativeLockSystemActiveState: Codable {
    let transactionID: UUID
    let assetID: UUID
}

private extension JSONEncoder {
    static var nativeSystemEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var nativeSystemDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
