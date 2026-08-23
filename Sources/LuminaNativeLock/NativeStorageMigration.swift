import Foundation

/// A one-time, recoverable merge from the old Hikari support directory into
/// the canonical Lumina support directory. The directory name is retained so
/// existing Lumina installations keep their library and settings in place.
public struct NativeStorageMigrationReport: Equatable {
    public let didMigrate: Bool
    public let migratedContentCount: Int
    public let migratedTransactionCount: Int
    public let requiresRestore: Bool
    public let archivedLegacyRootURL: URL?

    public init(
        didMigrate: Bool,
        migratedContentCount: Int,
        migratedTransactionCount: Int,
        requiresRestore: Bool,
        archivedLegacyRootURL: URL?
    ) {
        self.didMigrate = didMigrate
        self.migratedContentCount = migratedContentCount
        self.migratedTransactionCount = migratedTransactionCount
        self.requiresRestore = requiresRestore
        self.archivedLegacyRootURL = archivedLegacyRootURL
    }

    public static let notNeeded = NativeStorageMigrationReport(
        didMigrate: false,
        migratedContentCount: 0,
        migratedTransactionCount: 0,
        requiresRestore: false,
        archivedLegacyRootURL: nil
    )
}

public enum NativeStorageMigrationError: LocalizedError, Equatable {
    case invalidRelativePath(String)
    case invalidContentsFile(String)
    case missingReferencedFile(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRelativePath(path):
            "The Hikari library contains an unsafe relative path: \(path)"
        case let .invalidContentsFile(path):
            "The Hikari library contents file could not be read: \(path)"
        case let .missingReferencedFile(path):
            "A migrated library item is missing its media file: \(path)"
        }
    }
}

/// Merges the former `LuminaNative` user container exactly once.
///
/// The canonical directory is never replaced wholesale: existing Lumina
/// records and files win conflicts, while missing Native Local records and
/// files are copied in. Native Lock transaction journals are copied before
/// the legacy directory is moved to a recoverable archive, so an active or
/// recovery-required transaction remains visible to the new app and can be
/// restored before updates are allowed.
public enum NativeStorageMigration {
    public static let legacyDirectoryName = "LuminaNative"
    public static let migrationMarkerFilename = "hikari-storage-migration.json"

    private static let migratedFilesDirectoryName = "MigratedLuminaNative"

    public static func migrate(
        canonicalRootURL: URL,
        legacyRootURL: URL,
        userID: UInt32,
        fileManager: FileManager = .default
    ) throws -> NativeStorageMigrationReport {
        let canonicalRoot = canonicalRootURL.standardizedFileURL
        let legacyRoot = legacyRootURL.standardizedFileURL
        guard canonicalRoot != legacyRoot else {
            return .notNeeded
        }

        let markerURL = canonicalRoot.appendingPathComponent(
            migrationMarkerFilename
        )
        if fileManager.fileExists(atPath: markerURL.path) {
            return try readMarker(at: markerURL)
        }
        guard fileManager.fileExists(atPath: legacyRoot.path) else {
            return .notNeeded
        }

        try fileManager.createDirectory(
            at: canonicalRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let contentCount = try mergeContents(
            from: legacyRoot,
            into: canonicalRoot,
            fileManager: fileManager
        )
        try copyIfMissing(
            named: "settings.json",
            from: legacyRoot,
            into: canonicalRoot,
            fileManager: fileManager
        )
        try copyIfMissing(
            named: "CustomAppIcon.png",
            from: legacyRoot,
            into: canonicalRoot,
            fileManager: fileManager
        )
        try copyIfMissing(
            named: "CustomMenuBarIcon.png",
            from: legacyRoot,
            into: canonicalRoot,
            fileManager: fileManager
        )
        // macOS 15 Native Lock keeps the user's wallpaper mapping beside the
        // transaction journal. Preserve it so a migrated transaction can be
        // restored before Hikari attempts any new update or apply operation.
        try copyIfMissing(
            named: "Index.plist",
            from: legacyRoot,
            into: canonicalRoot,
            fileManager: fileManager
        )

        let legacyStore = NativeLockUserTransactionStore(
            supportRootURL: legacyRoot,
            wallpaperIndexURL: legacyRoot.appendingPathComponent("Index.plist"),
            userID: userID,
            fileManager: fileManager
        )
        let legacyRecords = try nonRestoredRecords(
            in: legacyStore,
            fileManager: fileManager
        )
        let transactionCount = try copyTransactions(
            from: legacyStore,
            into: NativeLockUserTransactionStore(
                supportRootURL: canonicalRoot,
                wallpaperIndexURL: canonicalRoot.appendingPathComponent("Index.plist"),
                userID: userID,
                fileManager: fileManager
            ),
            fileManager: fileManager
        )

        let archiveURL = try archiveLegacyRoot(
            legacyRoot,
            fileManager: fileManager
        )
        let report = NativeStorageMigrationReport(
            didMigrate: true,
            migratedContentCount: contentCount,
            migratedTransactionCount: transactionCount,
            requiresRestore: !legacyRecords.isEmpty,
            archivedLegacyRootURL: archiveURL
        )
        try writeMarker(report, to: markerURL, fileManager: fileManager)
        return report
    }

    private struct Marker: Codable {
        let schemaVersion: Int
        let didMigrate: Bool
        let migratedContentCount: Int
        let migratedTransactionCount: Int
        let requiresRestore: Bool
        let archivedLegacyRootPath: String?
    }

    private static func readMarker(
        at url: URL
    ) throws -> NativeStorageMigrationReport {
        let decoder = JSONDecoder()
        let marker = try decoder.decode(Marker.self, from: Data(contentsOf: url))
        guard marker.schemaVersion == 1 else {
            throw NativeStorageMigrationError.invalidContentsFile(url.path)
        }
        return NativeStorageMigrationReport(
            didMigrate: marker.didMigrate,
            migratedContentCount: marker.migratedContentCount,
            migratedTransactionCount: marker.migratedTransactionCount,
            requiresRestore: marker.requiresRestore,
            archivedLegacyRootURL: marker.archivedLegacyRootPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        )
    }

    private static func writeMarker(
        _ report: NativeStorageMigrationReport,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let marker = Marker(
            schemaVersion: 1,
            didMigrate: report.didMigrate,
            migratedContentCount: report.migratedContentCount,
            migratedTransactionCount: report.migratedTransactionCount,
            requiresRestore: report.requiresRestore,
            archivedLegacyRootPath: report.archivedLegacyRootURL?.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try encoder.encode(marker).write(to: url, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func mergeContents(
        from legacyRoot: URL,
        into canonicalRoot: URL,
        fileManager: FileManager
    ) throws -> Int {
        let legacyContentsURL = legacyRoot.appendingPathComponent("contents.json")
        guard fileManager.fileExists(atPath: legacyContentsURL.path) else {
            return 0
        }
        let legacyItems = try contentsArray(
            at: legacyContentsURL,
            fileManager: fileManager
        )
        let canonicalContentsURL = canonicalRoot.appendingPathComponent("contents.json")
        let canonicalItems: [[String: Any]]
        if fileManager.fileExists(atPath: canonicalContentsURL.path) {
            canonicalItems = try contentsArray(
                at: canonicalContentsURL,
                fileManager: fileManager
            )
        } else {
            canonicalItems = []
        }

        var mergedItems = canonicalItems
        var canonicalIDs = Set<String>()
        for item in canonicalItems {
            if let id = item["id"] as? String {
                canonicalIDs.insert(id)
            }
        }

        var migratedCount = 0
        for item in legacyItems {
            guard let id = item["id"] as? String else {
                throw NativeStorageMigrationError.invalidContentsFile(
                    legacyContentsURL.path
                )
            }
            guard !canonicalIDs.contains(id) else { continue }
            var migratedItem = item
            let itemID = UUID(uuidString: id) ?? UUID()
            if let relativePath = item["relativePath"] as? String {
                migratedItem["relativePath"] = try migrateReferencedFile(
                    relativePath,
                    itemID: itemID,
                    from: legacyRoot,
                    into: canonicalRoot,
                    fileManager: fileManager
                )
            }
            if let thumbnailPath = item["thumbnailRelativePath"] as? String {
                migratedItem["thumbnailRelativePath"] = try migrateReferencedFile(
                    thumbnailPath,
                    itemID: itemID,
                    from: legacyRoot,
                    into: canonicalRoot,
                    fileManager: fileManager
                )
            }
            mergedItems.append(migratedItem)
            canonicalIDs.insert(id)
            migratedCount += 1
        }

        guard JSONSerialization.isValidJSONObject(mergedItems) else {
            throw NativeStorageMigrationError.invalidContentsFile(
                canonicalContentsURL.path
            )
        }
        let data = try JSONSerialization.data(
            withJSONObject: mergedItems,
            options: [.prettyPrinted, .sortedKeys]
        )
        try fileManager.createDirectory(
            at: canonicalRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: canonicalContentsURL, options: .atomic)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: canonicalContentsURL.path
        )
        return migratedCount
    }

    private static func contentsArray(
        at url: URL,
        fileManager: FileManager
    ) throws -> [[String: Any]] {
        do {
            let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: url),
                options: []
            )
            guard let items = object as? [[String: Any]] else {
                throw NativeStorageMigrationError.invalidContentsFile(url.path)
            }
            return items
        } catch let error as NativeStorageMigrationError {
            throw error
        } catch {
            throw NativeStorageMigrationError.invalidContentsFile(url.path)
        }
    }

    private static func migrateReferencedFile(
        _ relativePath: String,
        itemID: UUID,
        from legacyRoot: URL,
        into canonicalRoot: URL,
        fileManager: FileManager
    ) throws -> String {
        let sourceURL = try safeURL(relativePath, under: legacyRoot)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NativeStorageMigrationError.missingReferencedFile(relativePath)
        }
        let destinationURL = try safeURL(relativePath, under: canonicalRoot)
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try copyItem(
                from: sourceURL,
                to: destinationURL,
                fileManager: fileManager
            )
            return relativePath
        }
        let sourceData = try Data(contentsOf: sourceURL)
        let destinationData = try Data(contentsOf: destinationURL)
        if sourceData == destinationData {
            return relativePath
        }

        let filename = URL(fileURLWithPath: relativePath).lastPathComponent
        var migratedRelativePath = "\(migratedFilesDirectoryName)/\(itemID.uuidString)-\(filename)"
        var counter = 0
        while fileManager.fileExists(
            atPath: canonicalRoot.appendingPathComponent(migratedRelativePath).path
        ) {
            counter += 1
            migratedRelativePath = "\(migratedFilesDirectoryName)/\(itemID.uuidString)-\(counter)-\(filename)"
        }
        let migratedURL = try safeURL(migratedRelativePath, under: canonicalRoot)
        try copyItem(from: sourceURL, to: migratedURL, fileManager: fileManager)
        return migratedRelativePath
    }

    private static func copyIfMissing(
        named name: String,
        from sourceRoot: URL,
        into destinationRoot: URL,
        fileManager: FileManager
    ) throws {
        let sourceURL = sourceRoot.appendingPathComponent(name)
        let destinationURL = destinationRoot.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: sourceURL.path),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            return
        }
        try copyItem(from: sourceURL, to: destinationURL, fileManager: fileManager)
    }

    private static func nonRestoredRecords(
        in store: NativeLockUserTransactionStore,
        fileManager: FileManager
    ) throws -> [NativeLockTransactionRecord] {
        guard fileManager.fileExists(atPath: store.transactionsDirectoryURL.path) else {
            return []
        }
        let entries = try fileManager.contentsOfDirectory(
            at: store.transactionsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        return try entries.compactMap { entry in
            guard let id = UUID(uuidString: entry.lastPathComponent) else {
                return nil
            }
            let record = try store.record(for: id)
            return record.journal.phase == .restored ? nil : record
        }
    }

    private static func copyTransactions(
        from source: NativeLockUserTransactionStore,
        into destination: NativeLockUserTransactionStore,
        fileManager: FileManager
    ) throws -> Int {
        guard fileManager.fileExists(atPath: source.transactionsDirectoryURL.path) else {
            return 0
        }
        try fileManager.createDirectory(
            at: destination.transactionsDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let entries = try fileManager.contentsOfDirectory(
            at: source.transactionsDirectoryURL,
            includingPropertiesForKeys: nil
        )
        var copiedCount = 0
        for entry in entries {
            guard UUID(uuidString: entry.lastPathComponent) != nil else { continue }
            let destinationURL = destination.transactionsDirectoryURL
                .appendingPathComponent(entry.lastPathComponent, isDirectory: true)
            guard !fileManager.fileExists(atPath: destinationURL.path) else { continue }
            try fileManager.copyItem(at: entry, to: destinationURL)
            copiedCount += 1
        }

        let sourceMarker = source.activeTransactionURL
        let destinationMarker = destination.activeTransactionURL
        if fileManager.fileExists(atPath: sourceMarker.path),
           !fileManager.fileExists(atPath: destinationMarker.path) {
            try copyItem(
                from: sourceMarker,
                to: destinationMarker,
                fileManager: fileManager
            )
        }
        return copiedCount
    }

    private static func archiveLegacyRoot(
        _ legacyRoot: URL,
        fileManager: FileManager
    ) throws -> URL {
        let parentURL = legacyRoot.deletingLastPathComponent()
        let baseURL = parentURL.appendingPathComponent(
            "\(legacyRoot.lastPathComponent).archived",
            isDirectory: true
        )
        var archiveURL = baseURL
        if fileManager.fileExists(atPath: archiveURL.path) {
            archiveURL = parentURL.appendingPathComponent(
                "\(legacyRoot.lastPathComponent).archived-\(UUID().uuidString)",
                isDirectory: true
            )
        }
        try fileManager.moveItem(at: legacyRoot, to: archiveURL)
        return archiveURL
    }

    private static func copyItem(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destinationURL.path
        )
    }

    private static func safeURL(
        _ relativePath: String,
        under rootURL: URL
    ) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !relativePath.hasPrefix("/"),
              !components.contains(where: { $0 == ".." }),
              !components.isEmpty else {
            throw NativeStorageMigrationError.invalidRelativePath(relativePath)
        }
        let root = rootURL.standardizedFileURL
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else {
            throw NativeStorageMigrationError.invalidRelativePath(relativePath)
        }
        return url
    }
}
