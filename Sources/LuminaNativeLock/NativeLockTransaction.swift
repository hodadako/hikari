import CryptoKit
import Darwin
import Foundation

public enum NativeLockTransactionPhase: String, Codable, Sendable {
    case prepared
    case systemApplied
    case active
    case restoring
    case restored
    case recoveryRequired
}

public enum NativeLockTransactionBackend: String, Codable, Sendable {
    /// The macOS 15 root-owned idleassets catalog transaction.
    case systemCatalog
    /// The macOS 26 per-user Aerial manifest transaction.
    case userAerials
}

public struct NativeLockRequest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let transactionID: UUID
    public let assetID: UUID
    public let sourceContentID: UUID
    public let userID: UInt32
    public let title: String
    public let mediaSHA256: String
    public let previewSHA256: String
    public let createdAt: Date

    public init(
        transactionID: UUID,
        assetID: UUID,
        sourceContentID: UUID,
        userID: UInt32,
        title: String,
        mediaSHA256: String,
        previewSHA256: String,
        createdAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.transactionID = transactionID
        self.assetID = assetID
        self.sourceContentID = sourceContentID
        self.userID = userID
        self.title = title
        self.mediaSHA256 = mediaSHA256
        self.previewSHA256 = previewSHA256
        self.createdAt = createdAt
    }
}

public struct NativeLockJournal: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let transactionID: UUID
    public let assetID: UUID
    public var phase: NativeLockTransactionPhase
    public var originalWallpaperIndexSHA256: String
    public var appliedWallpaperIndexSHA256: String?
    /// Reconciliation may add display/Space choices that did not exist in the
    /// original byte-for-byte backup. In that case restore must merge choices
    /// into the current topology instead of replacing the entire index.
    public var requiresSelectiveWallpaperRestore: Bool?
    /// Optional so journals created before the backend split remain readable.
    public var backend: NativeLockTransactionBackend?
    /// macOS 26 keeps its active Aerial manifest in the user domain. Its
    /// original digest protects the byte-for-byte rollback copy.
    public var originalModernManifestSHA256: String?
    public var systemManifestAppliedSHA256: String?
    public var lastError: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        transactionID: UUID,
        assetID: UUID,
        phase: NativeLockTransactionPhase,
        originalWallpaperIndexSHA256: String,
        appliedWallpaperIndexSHA256: String? = nil,
        requiresSelectiveWallpaperRestore: Bool? = nil,
        backend: NativeLockTransactionBackend? = nil,
        originalModernManifestSHA256: String? = nil,
        systemManifestAppliedSHA256: String? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = Self.schemaVersion
        self.transactionID = transactionID
        self.assetID = assetID
        self.phase = phase
        self.originalWallpaperIndexSHA256 = originalWallpaperIndexSHA256
        self.appliedWallpaperIndexSHA256 = appliedWallpaperIndexSHA256
        self.requiresSelectiveWallpaperRestore = requiresSelectiveWallpaperRestore
        self.backend = backend
        self.originalModernManifestSHA256 = originalModernManifestSHA256
        self.systemManifestAppliedSHA256 = systemManifestAppliedSHA256
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct NativeLockTransactionRecord: Equatable, Sendable {
    public let request: NativeLockRequest
    public let journal: NativeLockJournal

    public init(request: NativeLockRequest, journal: NativeLockJournal) {
        self.request = request
        self.journal = journal
    }
}

public enum NativeLockTransactionError: LocalizedError, Equatable {
    case unsupportedSchema
    case invalidIdentifier
    case invalidHash
    case invalidWallpaperStore
    case noWallpaperChoices
    case wallpaperMappingRejected
    case activeTransactionExists
    case transactionNotFound
    case transactionMismatch
    case sourceMissing
    case sourceNotRegularFile
    case sourceOwnerMismatch
    case sourceHashMismatch
    case unsafeSystemPath(String)
    case unsupportedOperatingSystem(Int)
    case systemManifestChanged
    case systemAssetChanged
    case helperMissing
    case helperFailed(String)
    /// The macOS 26 per-user Aerial catalog has not been initialized.
    case aerialCatalogMissing
    /// A legacy system-catalog transaction cannot be restored on the current OS.
    case legacyTransactionUnsupportedOnCurrentOperatingSystem(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema:
            "The native wallpaper schema is not supported on this Mac."
        case .invalidIdentifier:
            "The native transaction contains an invalid identifier."
        case .invalidHash:
            "The native transaction contains an invalid file hash."
        case .invalidWallpaperStore:
            "The macOS wallpaper store could not be validated."
        case .noWallpaperChoices:
            "No wallpaper choices were found to update."
        case .wallpaperMappingRejected:
            "macOS did not retain the Native Lock wallpaper mapping."
        case .activeTransactionExists:
            "Restore the current Native Lock transaction before applying another video."
        case .transactionNotFound:
            "The Native Lock transaction could not be found."
        case .transactionMismatch:
            "The Native Lock transaction does not match the active system state."
        case .sourceMissing:
            "A prepared Native Lock file is missing."
        case .sourceNotRegularFile:
            "A prepared Native Lock file is not a regular file."
        case .sourceOwnerMismatch:
            "A prepared Native Lock file is not owned by the requesting user."
        case .sourceHashMismatch:
            "A prepared Native Lock file changed after validation."
        case let .unsafeSystemPath(path):
            "A Native Lock system path is unsafe: \(path)"
        case let .unsupportedOperatingSystem(majorVersion):
            "Native Lock system writes are not enabled for macOS \(majorVersion)."
        case .systemManifestChanged:
            "The system aerial manifest changed during the transaction."
        case .systemAssetChanged:
            "A staged system asset changed after Hikari applied it."
        case .helperMissing:
            "The Native Lock privileged helper is missing from this local build."
        case let .helperFailed(message):
            "The Native Lock helper failed: \(message)"
        case .aerialCatalogMissing:
            "Initialize Apple Aerial wallpapers first."
        case let .legacyTransactionUnsupportedOnCurrentOperatingSystem(majorVersion):
            "The legacy system-catalog transaction cannot be used on macOS \(majorVersion). Restore using the original macOS version."
        }
    }
}

public enum NativeLockPaths {
    public static let transactionsDirectoryName = "NativeLockTransactions"
    public static let activeTransactionFilename = "native-lock-active.json"
    public static let requestFilename = "request.json"
    public static let journalFilename = "journal.json"
    public static let originalWallpaperIndexFilename = "Index.original.plist"
    public static let originalModernManifestFilename = "Aerial.entries.original.json"
    public static let restoreOverlayFilename = "Index.restore-overlay.plist"
    public static let stagedMediaFilename = "media.mov"
    public static let stagedPreviewFilename = "preview.jpg"

    public static let systemSupportRoot = URL(
        fileURLWithPath: "/Library/Application Support/com.hodadako.LuminaNative",
        isDirectory: true
    )
    public static let idleAssetsRoot = URL(
        fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd",
        isDirectory: true
    )
}

public enum NativeLockDigest {
    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
    }
}

public final class NativeLockUserTransactionStore: @unchecked Sendable {
    public let supportRootURL: URL
    public let wallpaperIndexURL: URL
    public let userID: UInt32

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        supportRootURL: URL,
        wallpaperIndexURL: URL,
        userID: UInt32,
        fileManager: FileManager = .default
    ) {
        self.supportRootURL = supportRootURL
        self.wallpaperIndexURL = wallpaperIndexURL
        self.userID = userID
        self.fileManager = fileManager
        self.encoder = JSONEncoder.nativeLockEncoder
        self.decoder = JSONDecoder.nativeLockDecoder
    }

    public var transactionsDirectoryURL: URL {
        supportRootURL.appendingPathComponent(
            NativeLockPaths.transactionsDirectoryName,
            isDirectory: true
        )
    }

    public var activeTransactionURL: URL {
        supportRootURL.appendingPathComponent(
            NativeLockPaths.activeTransactionFilename
        )
    }

    public func transactionDirectoryURL(for transactionID: UUID) -> URL {
        transactionsDirectoryURL.appendingPathComponent(
            transactionID.uuidString,
            isDirectory: true
        )
    }

    public func prepare(
        sourceContentID: UUID,
        title: String,
        preparedMediaURL: URL,
        preparedPreviewURL: URL
    ) throws -> NativeLockTransactionRecord {
        if try activeOrPendingTransaction() != nil {
            throw NativeLockTransactionError.activeTransactionExists
        }

        let transactionID = UUID()
        let assetID = UUID()
        let transactionURL = transactionDirectoryURL(for: transactionID)
        try fileManager.createDirectory(
            at: transactionURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            let stagedMediaURL = transactionURL.appendingPathComponent(
                NativeLockPaths.stagedMediaFilename
            )
            let stagedPreviewURL = transactionURL.appendingPathComponent(
                NativeLockPaths.stagedPreviewFilename
            )
            try fileManager.copyItem(at: preparedMediaURL, to: stagedMediaURL)
            try fileManager.copyItem(at: preparedPreviewURL, to: stagedPreviewURL)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stagedMediaURL.path
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: stagedPreviewURL.path
            )
            try synchronizeFileAndParent(stagedMediaURL)
            try synchronizeFileAndParent(stagedPreviewURL)

            let originalIndexData = try Data(contentsOf: wallpaperIndexURL)
            _ = try Self.wallpaperDictionary(from: originalIndexData)
            let originalIndexURL = transactionURL.appendingPathComponent(
                NativeLockPaths.originalWallpaperIndexFilename
            )
            try originalIndexData.write(to: originalIndexURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: originalIndexURL.path
            )
            try synchronizeFileAndParent(originalIndexURL)

            let request = NativeLockRequest(
                transactionID: transactionID,
                assetID: assetID,
                sourceContentID: sourceContentID,
                userID: userID,
                title: Self.sanitizedTitle(title),
                mediaSHA256: try NativeLockDigest.sha256(of: stagedMediaURL),
                previewSHA256: try NativeLockDigest.sha256(of: stagedPreviewURL)
            )
            let journal = NativeLockJournal(
                transactionID: transactionID,
                assetID: assetID,
                phase: .prepared,
                originalWallpaperIndexSHA256: NativeLockDigest.sha256(
                    of: originalIndexData
                )
            )
            try write(request, to: requestURL(for: transactionID))
            try write(journal, to: journalURL(for: transactionID))
            return NativeLockTransactionRecord(request: request, journal: journal)
        } catch {
            try? fileManager.removeItem(at: transactionURL)
            throw error
        }
    }

    public func record(for transactionID: UUID) throws -> NativeLockTransactionRecord {
        let request: NativeLockRequest = try read(
            NativeLockRequest.self,
            from: requestURL(for: transactionID)
        )
        let journal: NativeLockJournal = try read(
            NativeLockJournal.self,
            from: journalURL(for: transactionID)
        )
        guard request.schemaVersion == NativeLockRequest.schemaVersion,
              journal.schemaVersion == NativeLockJournal.schemaVersion,
              request.transactionID == transactionID,
              journal.transactionID == transactionID,
              request.assetID == journal.assetID else {
            throw NativeLockTransactionError.unsupportedSchema
        }
        return NativeLockTransactionRecord(request: request, journal: journal)
    }

    public func activeOrPendingTransaction() throws -> NativeLockTransactionRecord? {
        if fileManager.fileExists(atPath: activeTransactionURL.path) {
            let marker: ActiveTransactionMarker = try read(
                ActiveTransactionMarker.self,
                from: activeTransactionURL
            )
            let markedRecord = try record(for: marker.transactionID)
            if markedRecord.journal.phase != .restored {
                return markedRecord
            }
            try fileManager.removeItem(at: activeTransactionURL)
        }

        guard let entries = try? fileManager.contentsOfDirectory(
            at: transactionsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        let records = entries.compactMap { entry -> NativeLockTransactionRecord? in
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let record = try? record(for: id),
                  record.journal.phase != .restored else {
                return nil
            }
            return record
        }
        return records.sorted { $0.journal.updatedAt > $1.journal.updatedAt }.first
    }

    public func markSystemApplied(
        transactionID: UUID,
        manifestSHA256: String,
        backend: NativeLockTransactionBackend = .systemCatalog,
        originalModernManifestSHA256: String? = nil
    ) throws -> NativeLockTransactionRecord {
        guard NativeLockDigest.isValidSHA256(manifestSHA256) else {
            throw NativeLockTransactionError.invalidHash
        }
        if let originalModernManifestSHA256,
           !NativeLockDigest.isValidSHA256(originalModernManifestSHA256) {
            throw NativeLockTransactionError.invalidHash
        }
        return try updateJournal(transactionID: transactionID) { journal in
            journal.phase = .systemApplied
            journal.backend = backend
            journal.originalModernManifestSHA256 = originalModernManifestSHA256
            journal.systemManifestAppliedSHA256 = manifestSHA256
            journal.lastError = nil
        }
    }

    public func applyWallpaperMapping(
        transactionID: UUID
    ) throws -> NativeLockTransactionRecord {
        try applyWallpaperMapping(transactionID: transactionID, scope: .all)
    }

    /// macOS 26 accepts custom Aerial assets for the Lock Screen's linked
    /// choices. Desktop and Idle choices are intentionally left untouched.
    public func applyLinkedWallpaperMapping(
        transactionID: UUID
    ) throws -> NativeLockTransactionRecord {
        try applyWallpaperMapping(transactionID: transactionID, scope: .linked)
    }

    private func applyWallpaperMapping(
        transactionID: UUID,
        scope: WallpaperChoiceScope
    ) throws -> NativeLockTransactionRecord {
        let current = try record(for: transactionID)
        let currentData = try Data(contentsOf: wallpaperIndexURL)
        let currentDictionary = try Self.wallpaperDictionary(from: currentData)
        if current.journal.phase == .systemApplied {
            let originalURL = transactionDirectoryURL(for: transactionID)
                .appendingPathComponent(
                    NativeLockPaths.originalWallpaperIndexFilename
                )
            try currentData.write(to: originalURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: originalURL.path
            )
            try synchronizeFileAndParent(originalURL)
            _ = try updateJournal(transactionID: transactionID) { journal in
                journal.originalWallpaperIndexSHA256 = NativeLockDigest.sha256(
                    of: currentData
                )
                journal.lastError = nil
            }
        }
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": current.request.assetID.uuidString],
            format: .binary,
            options: 0
        )
        let (updatedValue, replacements) = Self.replacingWallpaperChoices(
            in: currentDictionary,
            configuration: configuration,
            scope: scope
        )
        guard replacements > 0,
              let updatedDictionary = updatedValue as? [String: Any] else {
            throw NativeLockTransactionError.noWallpaperChoices
        }
        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: updatedDictionary,
            format: .binary,
            options: 0
        )
        try updatedData.write(to: wallpaperIndexURL, options: .atomic)
        try synchronizeFileAndParent(wallpaperIndexURL)
        let updatedHash = NativeLockDigest.sha256(of: updatedData)
        let updatedRecord = try updateJournal(transactionID: transactionID) { journal in
            journal.phase = .active
            journal.appliedWallpaperIndexSHA256 = updatedHash
            journal.lastError = nil
        }
        try write(
            ActiveTransactionMarker(transactionID: transactionID),
            to: activeTransactionURL
        )
        return updatedRecord
    }

    public func wallpaperMappingMatches(transactionID: UUID) throws -> Bool {
        try wallpaperMappingMatches(transactionID: transactionID, scope: .all)
    }

    public func linkedWallpaperMappingMatches(transactionID: UUID) throws -> Bool {
        try wallpaperMappingMatches(transactionID: transactionID, scope: .linked)
    }

    private func wallpaperMappingMatches(
        transactionID: UUID,
        scope: WallpaperChoiceScope
    ) throws -> Bool {
        let record = try record(for: transactionID)
        let data = try Data(contentsOf: wallpaperIndexURL)
        let dictionary = try Self.wallpaperDictionary(from: data)
        let counts = Self.wallpaperChoiceCounts(
            in: dictionary,
            matching: record.request.assetID.uuidString,
            scope: scope
        )
        return counts.total > 0 && counts.total == counts.matching
    }

    /// Repairs choices created or reset after the initial apply without
    /// touching the privileged system asset. Any non-Lumina choice that will
    /// be replaced is saved by its exact topology path so restore can preserve
    /// displays and Spaces that did not exist in the original index.
    @discardableResult
    public func reconcileWallpaperMapping(
        transactionID: UUID
    ) throws -> NativeLockTransactionRecord {
        try reconcileWallpaperMapping(transactionID: transactionID, scope: .all)
    }

    public func reconcileLinkedWallpaperMapping(
        transactionID: UUID
    ) throws -> NativeLockTransactionRecord {
        try reconcileWallpaperMapping(transactionID: transactionID, scope: .linked)
    }

    private func reconcileWallpaperMapping(
        transactionID: UUID,
        scope: WallpaperChoiceScope
    ) throws -> NativeLockTransactionRecord {
        let current = try record(for: transactionID)
        guard current.journal.phase == .active else {
            throw NativeLockTransactionError.transactionMismatch
        }
        let currentData = try Data(contentsOf: wallpaperIndexURL)
        let currentDictionary = try Self.wallpaperDictionary(from: currentData)
        let counts = Self.wallpaperChoiceCounts(
            in: currentDictionary,
            matching: current.request.assetID.uuidString,
            scope: scope
        )
        guard counts.total > 0 else {
            throw NativeLockTransactionError.noWallpaperChoices
        }
        guard counts.total != counts.matching else { return current }

        let transactionURL = transactionDirectoryURL(for: transactionID)
        let overlayURL = transactionURL.appendingPathComponent(
            NativeLockPaths.restoreOverlayFilename
        )
        var restoreChoices = try restoreOverlayChoices(at: overlayURL)
        Self.collectNonMatchingWallpaperChoices(
            in: currentDictionary,
            path: [],
            assetID: current.request.assetID.uuidString,
            scope: scope,
            choices: &restoreChoices
        )
        let overlayData = try PropertyListSerialization.data(
            fromPropertyList: restoreChoices,
            format: .binary,
            options: 0
        )
        try overlayData.write(to: overlayURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: overlayURL.path
        )
        try synchronizeFileAndParent(overlayURL)

        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": current.request.assetID.uuidString],
            format: .binary,
            options: 0
        )
        let (updatedValue, replacements) = Self.replacingWallpaperChoices(
            in: currentDictionary,
            configuration: configuration,
            scope: scope
        )
        guard replacements == counts.total,
              let updatedDictionary = updatedValue as? [String: Any] else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        let updatedData = try PropertyListSerialization.data(
            fromPropertyList: updatedDictionary,
            format: .binary,
            options: 0
        )
        try updatedData.write(to: wallpaperIndexURL, options: .atomic)
        try synchronizeFileAndParent(wallpaperIndexURL)
        return try updateJournal(transactionID: transactionID) { journal in
            journal.appliedWallpaperIndexSHA256 = NativeLockDigest.sha256(
                of: updatedData
            )
            journal.requiresSelectiveWallpaperRestore = true
            journal.lastError = nil
        }
    }

    public func beginRestore(
        transactionID: UUID
    ) throws -> NativeLockTransactionRecord {
        try updateJournal(transactionID: transactionID) { journal in
            journal.phase = .restoring
            journal.lastError = nil
        }
    }

    public func restoreWallpaperMapping(transactionID: UUID) throws {
        let record = try record(for: transactionID)
        let originalURL = transactionDirectoryURL(for: transactionID)
            .appendingPathComponent(NativeLockPaths.originalWallpaperIndexFilename)
        let originalData = try Data(contentsOf: originalURL)
        guard NativeLockDigest.sha256(of: originalData)
                == record.journal.originalWallpaperIndexSHA256 else {
            throw NativeLockTransactionError.invalidHash
        }
        let originalDictionary = try Self.wallpaperDictionary(from: originalData)
        let currentData = try Data(contentsOf: wallpaperIndexURL)
        let currentDictionary = try Self.wallpaperDictionary(from: currentData)
        let overlayURL = transactionDirectoryURL(for: transactionID)
            .appendingPathComponent(NativeLockPaths.restoreOverlayFilename)
        let restoreOverlay = try restoreOverlayChoices(at: overlayURL)

        let restoredData: Data
        if record.journal.requiresSelectiveWallpaperRestore != true,
           let appliedHash = record.journal.appliedWallpaperIndexSHA256,
           NativeLockDigest.sha256(of: currentData) == appliedHash {
            restoredData = originalData
        } else {
            let merged = Self.restoringWallpaperChoices(
                current: currentDictionary,
                original: originalDictionary,
                restoreOverlay: restoreOverlay,
                assetID: record.request.assetID.uuidString
            )
            guard let mergedDictionary = merged as? [String: Any] else {
                throw NativeLockTransactionError.invalidWallpaperStore
            }
            restoredData = try PropertyListSerialization.data(
                fromPropertyList: mergedDictionary,
                format: .binary,
                options: 0
            )
        }
        try restoredData.write(to: wallpaperIndexURL, options: .atomic)
        try synchronizeFileAndParent(wallpaperIndexURL)
    }

    public func markRestored(transactionID: UUID) throws {
        _ = try updateJournal(transactionID: transactionID) { journal in
            journal.phase = .restored
            journal.lastError = nil
        }
        if fileManager.fileExists(atPath: activeTransactionURL.path) {
            let marker = try? read(
                ActiveTransactionMarker.self,
                from: activeTransactionURL
            )
            if marker?.transactionID == transactionID {
                try fileManager.removeItem(at: activeTransactionURL)
            }
        }
    }

    public func markRecoveryRequired(
        transactionID: UUID,
        error: String
    ) throws {
        _ = try updateJournal(transactionID: transactionID) { journal in
            journal.phase = .recoveryRequired
            journal.lastError = error
        }
    }

    private func requestURL(for transactionID: UUID) -> URL {
        transactionDirectoryURL(for: transactionID)
            .appendingPathComponent(NativeLockPaths.requestFilename)
    }

    private func journalURL(for transactionID: UUID) -> URL {
        transactionDirectoryURL(for: transactionID)
            .appendingPathComponent(NativeLockPaths.journalFilename)
    }

    private func updateJournal(
        transactionID: UUID,
        mutation: (inout NativeLockJournal) -> Void
    ) throws -> NativeLockTransactionRecord {
        let request: NativeLockRequest = try read(
            NativeLockRequest.self,
            from: requestURL(for: transactionID)
        )
        var journal: NativeLockJournal = try read(
            NativeLockJournal.self,
            from: journalURL(for: transactionID)
        )
        mutation(&journal)
        journal.updatedAt = Date()
        try write(journal, to: journalURL(for: transactionID))
        return NativeLockTransactionRecord(request: request, journal: journal)
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try encoder.encode(value).write(to: url, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
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

    private static func wallpaperDictionary(from data: Data) throws -> [String: Any] {
        let value = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        guard let dictionary = value as? [String: Any],
              dictionary["SystemDefault"] != nil else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        return dictionary
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
        let parentDescriptor = open(
            url.deletingLastPathComponent().path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(parentDescriptor) }
        guard fsync(parentDescriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private enum WallpaperChoiceScope: Equatable {
        case all
        case linked
    }

    private static func replacingWallpaperChoices(
        in value: Any,
        configuration: Data,
        scope: WallpaperChoiceScope,
        isWithinLinkedContainer: Bool = false
    ) -> (Any, Int) {
        if var dictionary = value as? [String: Any] {
            if dictionary["Provider"] is String,
               dictionary["Configuration"] is Data,
               scope == .all || isWithinLinkedContainer {
                dictionary["Provider"] = "com.apple.wallpaper.choice.aerials"
                dictionary["Configuration"] = configuration
                dictionary["Files"] = [Any]()
                return (dictionary, 1)
            }
            var replacements = 0
            for key in dictionary.keys {
                let (updated, count) = replacingWallpaperChoices(
                    in: dictionary[key] as Any,
                    configuration: configuration,
                    scope: scope,
                    isWithinLinkedContainer: isWithinLinkedContainer || key == "Linked"
                )
                dictionary[key] = updated
                replacements += count
            }
            if replacements > 0,
               dictionary["Content"] is [String: Any],
               dictionary["LastSet"] is Date {
                dictionary["LastSet"] = Date()
                dictionary["LastUse"] = Date()
            }
            return (dictionary, replacements)
        }
        if let array = value as? [Any] {
            var replacements = 0
            let updated = array.map { item -> Any in
                let (replacement, count) = replacingWallpaperChoices(
                    in: item,
                    configuration: configuration,
                    scope: scope,
                    isWithinLinkedContainer: isWithinLinkedContainer
                )
                replacements += count
                return replacement
            }
            return (updated, replacements)
        }
        return (value, 0)
    }

    private static func restoringWallpaperChoices(
        current: Any,
        original: Any,
        restoreOverlay: [String: Any],
        assetID: String
    ) -> Any {
        var originalChoices: [String: [String: Any]] = [:]
        collectWallpaperChoices(
            in: original,
            path: [],
            choices: &originalChoices
        )
        let fallback = originalChoices
            .sorted { $0.key < $1.key }
            .first { $0.key.hasPrefix("SystemDefault|") }?.value
            ?? originalChoices.sorted { $0.key < $1.key }.first?.value
        return restoringWallpaperChoices(
            current: current,
            path: [],
            originalChoices: originalChoices,
            restoreOverlay: restoreOverlay,
            fallback: fallback,
            assetID: assetID
        )
    }

    private static func restoringWallpaperChoices(
        current: Any,
        path: [String],
        originalChoices: [String: [String: Any]],
        restoreOverlay: [String: Any],
        fallback: [String: Any]?,
        assetID: String
    ) -> Any {
        if let dictionary = current as? [String: Any] {
            if choiceAssetID(in: dictionary) == assetID {
                return restoreOverlay[wallpaperChoiceExactPathKey(path: path)]
                    as? [String: Any]
                    ?? originalChoices[wallpaperChoiceContextKey(path: path)]
                    ?? fallback
                    ?? dictionary
            }
            var restored = dictionary
            for key in dictionary.keys {
                restored[key] = restoringWallpaperChoices(
                    current: dictionary[key] as Any,
                    path: path + [key],
                    originalChoices: originalChoices,
                    restoreOverlay: restoreOverlay,
                    fallback: fallback,
                    assetID: assetID
                )
            }
            return restored
        }
        if let array = current as? [Any] {
            return array.enumerated().map { index, value in
                restoringWallpaperChoices(
                    current: value,
                    path: path + [String(index)],
                    originalChoices: originalChoices,
                    restoreOverlay: restoreOverlay,
                    fallback: fallback,
                    assetID: assetID
                )
            }
        }
        return current
    }

    private static func collectWallpaperChoices(
        in value: Any,
        path: [String],
        choices: inout [String: [String: Any]]
    ) {
        if let dictionary = value as? [String: Any] {
            if dictionary["Provider"] is String,
               dictionary["Configuration"] is Data {
                choices[wallpaperChoiceContextKey(path: path)] = dictionary
                return
            }
            for key in dictionary.keys.sorted() {
                collectWallpaperChoices(
                    in: dictionary[key] as Any,
                    path: path + [key],
                    choices: &choices
                )
            }
            return
        }
        if let array = value as? [Any] {
            for (index, item) in array.enumerated() {
                collectWallpaperChoices(
                    in: item,
                    path: path + [String(index)],
                    choices: &choices
                )
            }
        }
    }

    private static func wallpaperChoiceContextKey(path: [String]) -> String {
        let structuralKeys: Set<String> = [
            "Linked", "Desktop", "Idle", "Content", "Choices"
        ]
        return path.filter { !structuralKeys.contains($0) }.joined(separator: "|")
    }

    private static func wallpaperChoiceExactPathKey(path: [String]) -> String {
        path.joined(separator: "|")
    }

    private static func collectNonMatchingWallpaperChoices(
        in value: Any,
        path: [String],
        assetID: String,
        scope: WallpaperChoiceScope,
        isWithinLinkedContainer: Bool = false,
        choices: inout [String: Any]
    ) {
        if let dictionary = value as? [String: Any] {
            if dictionary["Provider"] is String,
               dictionary["Configuration"] is Data {
                if (scope == .all || isWithinLinkedContainer),
                   choiceAssetID(in: dictionary) != assetID {
                    choices[wallpaperChoiceExactPathKey(path: path)] = dictionary
                }
                return
            }
            for key in dictionary.keys.sorted() {
                collectNonMatchingWallpaperChoices(
                    in: dictionary[key] as Any,
                    path: path + [key],
                    assetID: assetID,
                    scope: scope,
                    isWithinLinkedContainer: isWithinLinkedContainer || key == "Linked",
                    choices: &choices
                )
            }
            return
        }
        if let array = value as? [Any] {
            for (index, item) in array.enumerated() {
                collectNonMatchingWallpaperChoices(
                    in: item,
                    path: path + [String(index)],
                    assetID: assetID,
                    scope: scope,
                    isWithinLinkedContainer: isWithinLinkedContainer,
                    choices: &choices
                )
            }
        }
    }

    private func restoreOverlayChoices(at url: URL) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let choices = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        return choices
    }

    private static func wallpaperChoiceCounts(
        in value: Any,
        matching assetID: String,
        scope: WallpaperChoiceScope,
        isWithinLinkedContainer: Bool = false
    ) -> (total: Int, matching: Int) {
        if let dictionary = value as? [String: Any] {
            if dictionary["Provider"] is String,
               dictionary["Configuration"] is Data {
                guard scope == .all || isWithinLinkedContainer else {
                    return (total: 0, matching: 0)
                }
                return (
                    total: 1,
                    matching: choiceAssetID(in: dictionary) == assetID ? 1 : 0
                )
            }
            return dictionary.reduce(into: (total: 0, matching: 0)) {
                result, entry in
                let counts = wallpaperChoiceCounts(
                    in: entry.value,
                    matching: assetID,
                    scope: scope,
                    isWithinLinkedContainer: isWithinLinkedContainer
                        || entry.key == "Linked"
                )
                result.total += counts.total
                result.matching += counts.matching
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: (total: 0, matching: 0)) { result, child in
                let counts = wallpaperChoiceCounts(
                    in: child,
                    matching: assetID,
                    scope: scope,
                    isWithinLinkedContainer: isWithinLinkedContainer
                )
                result.total += counts.total
                result.matching += counts.matching
            }
        }
        return (total: 0, matching: 0)
    }

    private static func choiceAssetID(in dictionary: [String: Any]) -> String? {
        guard dictionary["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
              let configuration = dictionary["Configuration"] as? Data,
              let decoded = try? PropertyListSerialization.propertyList(
                from: configuration,
                options: [],
                format: nil
              ) as? [String: Any] else {
            return nil
        }
        return decoded["assetID"] as? String
    }

    private static func sanitizedTitle(_ title: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((sanitized.isEmpty ? "Hikari Video" : sanitized).prefix(120))
    }
}

private struct ActiveTransactionMarker: Codable {
    let transactionID: UUID
}

private extension JSONEncoder {
    static var nativeLockEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var nativeLockDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
