import XCTest
@testable import HikariNativeLock

/// The real preference domain and wallpaper store are never accessed here.
final class NativeLockGoldenGateActivationTests: XCTestCase {
    private final class Preferences: NativeLockAerialPreferences {
        var values: [String: Any] = [:]
        var synchronizes = true
        var writes = 0
        func value(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value; writes += 1 }
        func synchronize() -> Bool { synchronizes }
    }
    private var root: URL!
    private var wallpaper: URL!
    private var bundled: URL!
    private var index: URL!
    private var prefs: Preferences!
    private var activation: NativeLockGoldenGateActivation!
    private var store: NativeLockUserTransactionStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Hikari27Activation-\(UUID())")
        wallpaper = root.appendingPathComponent("Wallpaper")
        index = wallpaper.appendingPathComponent("Store/Index.plist")
        bundled = root.appendingPathComponent("Bundle/entries.json")
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let fixture = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil)).appendingPathComponent("macOS27")
        for (source, destination) in [("Index.plist", index!), ("bundled-schema2.json", bundled!)] {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture.appendingPathComponent(source), to: destination)
        }
        prefs = Preferences()
        activation = makeActivation(27)
        store = NativeLockUserTransactionStore(supportRootURL: root.appendingPathComponent("Support"),
                                              wallpaperIndexURL: index, userID: UInt32(getuid()))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func makeActivation(_ os: Int) -> NativeLockGoldenGateActivation {
        NativeLockGoldenGateActivation(wallpaperRoot: wallpaper, bundledManifest: bundled,
                                      preferences: prefs, operatingSystemMajorVersion: os)
    }
    private func prepare() throws -> (NativeLockTransactionRecord, String) {
        let media = root.appendingPathComponent("source.mov"), preview = root.appendingPathComponent("source.png")
        try Data("movie fixture".utf8).write(to: media)
        try Data("preview fixture".utf8).write(to: preview)
        let record = try store.prepare(sourceContentID: UUID(), title: "Fixture", preparedMediaURL: media,
                                      preparedPreviewURL: preview, operatingSystemMajorVersion: 27)
        let hash = try activation.prepare(request: record.request, transactionURL: transaction(record))
        try store.markAerialActivationPrepared(transactionID: record.request.transactionID, sha256: hash)
        return (record, hash)
    }
    private func apply() throws -> (NativeLockTransactionRecord, String) {
        let (record, hash) = try prepare()
        let result = try manager(record).apply(request: record.request, sourceTransactionURL: transaction(record))
        _ = try store.markSystemApplied(transactionID: record.request.transactionID,
            manifestSHA256: result.manifestSHA256, backend: .userAerials27,
            originalModernManifestSHA256: result.originalManifestSHA256)
        try activation.activate(request: record.request, transactionURL: transaction(record), backupSHA256: hash)
        return (try store.applyLinkedWallpaperMapping(transactionID: record.request.transactionID), hash)
    }
    private func restore(_ record: NativeLockTransactionRecord, _ hash: String) throws {
        try activation.validateRestore(request: record.request, transactionURL: transaction(record), backupSHA256: hash)
        let original = try activation.originalCatalogSHA256(request: record.request, transactionURL: transaction(record), backupSHA256: hash)
        try store.validateWallpaperRestore(transactionID: record.request.transactionID)
        try manager(record).validateRestore(originalManifestSHA256: original, sourceTransactionURL: transaction(record))
        _ = try store.beginRestore(transactionID: record.request.transactionID)
        try store.restoreWallpaperMapping(transactionID: record.request.transactionID)
        try manager(record).restore(request: record.request, sourceTransactionURL: transaction(record),
            originalManifestSHA256: original, appliedManifestSHA256: record.journal.systemManifestAppliedSHA256)
        try activation.restore(request: record.request, transactionURL: transaction(record), backupSHA256: hash)
        try store.markRestored(transactionID: record.request.transactionID)
    }
    private func transaction(_ r: NativeLockTransactionRecord) -> URL { store.transactionDirectoryURL(for: r.request.transactionID) }
    private func manager(_ r: NativeLockTransactionRecord) -> NativeLockModernTransactionManager {
        NativeLockModernTransactionManager(environment: activation.environment(for: r.request))
    }

    func testOnlyGoldenGateAndSchemaTwoPassPreflight() throws {
        for os in [15, 26, 28] { XCTAssertThrowsError(try makeActivation(os).preflight()) }
        try activation.preflight()
        for version: Any in [1, 3, true] {
            try JSONSerialization.data(withJSONObject: ["version": version, "assets": [], "categories": []]).write(to: bundled)
            XCTAssertThrowsError(try activation.preflight())
        }
        XCTAssertEqual(prefs.writes, 0)
    }

    func testForeignOverrideRejectedWithoutAnyWrites() throws {
        prefs.values[NativeLockGoldenGateActivation.pathKey] = "/external/catalog.json"
        XCTAssertThrowsError(try prepare())
        XCTAssertEqual(prefs.writes, 0)
        XCTAssertEqual(prefs.value(forKey: NativeLockGoldenGateActivation.pathKey) as? String, "/external/catalog.json")
    }

    func testPreparationJournalsUndoBeforePreferencesAndLeavesCanonicalCatalogUntouched() throws {
        let canonical = wallpaper.appendingPathComponent("aerials/manifest/entries.json")
        try FileManager.default.createDirectory(at: canonical.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stale = Data(#"{"version":1,"assets":[],"categories":[]}"#.utf8)
        try stale.write(to: canonical)
        let (record, hash) = try prepare()
        XCTAssertEqual(record.journal.backend, .userAerials27)
        XCTAssertEqual(try store.record(for: record.request.transactionID).journal.aerialActivationSHA256, hash)
        XCTAssertEqual(prefs.writes, 0)
        XCTAssertEqual(try Data(contentsOf: activation.catalogURL(for: record.request)), try Data(contentsOf: bundled))
        XCTAssertEqual(try Data(contentsOf: canonical), stale)
        XCTAssertThrowsError(try activation.prepare(request: record.request, transactionURL: transaction(record)))
        let backup = transaction(record).appendingPathComponent(NativeLockGoldenGateActivation.backupFilename)
        let mode = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testActivationRequiresOwnedAssetAndVerifiedUndoRecord() throws {
        let (record, hash) = try prepare()
        XCTAssertThrowsError(try activation.activate(request: record.request, transactionURL: transaction(record), backupSHA256: hash))
        XCTAssertEqual(prefs.writes, 0)
        _ = try manager(record).apply(request: record.request, sourceTransactionURL: transaction(record))
        XCTAssertThrowsError(try activation.activate(request: record.request, transactionURL: transaction(record), backupSHA256: String(repeating: "0", count: 64)))
        XCTAssertEqual(prefs.writes, 0)
        try activation.activate(request: record.request, transactionURL: transaction(record), backupSHA256: hash)
        XCTAssertTrue(activation.selectionMatches(request: record.request))
    }

    func testApplyAndRestorePreserveAppleSchemaTwoRecordsAndOriginalPreferences() throws {
        for originalForce: Bool? in [nil, false, true] {
            prefs.values[NativeLockGoldenGateActivation.forceKey] = originalForce
            let beforeIndex = try Data(contentsOf: index), beforeCatalog = try Data(contentsOf: bundled)
            let (record, hash) = try apply()
            let catalog = try NativeLockSafetyInspector.aerialManifest(from: Data(contentsOf: activation.catalogURL(for: record.request)), schemaVersion: 2)
            let original = try NativeLockSafetyInspector.aerialManifest(from: beforeCatalog, schemaVersion: 2)
            XCTAssertEqual((catalog["assets"] as? [[String: Any]])?.count, 4)
            for asset in original["assets"] as! [[String: Any]] {
                let current = (catalog["assets"] as! [[String: Any]]).first { $0["id"] as? String == asset["id"] as? String }!
                XCTAssertTrue(NSDictionary(dictionary: asset).isEqual(to: current))
            }
            try restore(record, hash)
            XCTAssertNil(prefs.value(forKey: NativeLockGoldenGateActivation.pathKey))
            XCTAssertEqual(prefs.value(forKey: NativeLockGoldenGateActivation.forceKey) as? Bool, originalForce)
            XCTAssertEqual(try Data(contentsOf: index), beforeIndex)
            XCTAssertEqual(try Data(contentsOf: activation.catalogURL(for: record.request)), beforeCatalog)
            XCTAssertEqual(try Data(contentsOf: bundled), beforeCatalog)
            XCTAssertNil(try store.activeOrPendingTransaction())
        }
    }

    func testRestorePreservesAnotherWritersCatalogSelection() throws {
        let (record, hash) = try apply()
        prefs.values[NativeLockGoldenGateActivation.pathKey] = "/external/new.json"
        prefs.values[NativeLockGoldenGateActivation.forceKey] = false
        try restore(record, hash)
        XCTAssertEqual(prefs.value(forKey: NativeLockGoldenGateActivation.pathKey) as? String, "/external/new.json")
        XCTAssertEqual(prefs.value(forKey: NativeLockGoldenGateActivation.forceKey) as? Bool, false)
    }

    func testRestorePreservesExternalForceLocalChange() throws {
        let (record, hash) = try apply()
        prefs.values[NativeLockGoldenGateActivation.forceKey] = false
        try restore(record, hash)
        XCTAssertNil(prefs.value(forKey: NativeLockGoldenGateActivation.pathKey))
        XCTAssertEqual(prefs.value(forKey: NativeLockGoldenGateActivation.forceKey) as? Bool, false)
    }

    func testCorruptActivationBackupBlocksRestoreBeforeWrites() throws {
        let (record, hash) = try apply()
        let beforeIndex = try Data(contentsOf: index), writes = prefs.writes
        try Data("bad backup".utf8).write(to: transaction(record).appendingPathComponent(NativeLockGoldenGateActivation.backupFilename))
        XCTAssertThrowsError(try restore(record, hash))
        XCTAssertEqual(try Data(contentsOf: index), beforeIndex)
        XCTAssertEqual(prefs.writes, writes)
        XCTAssertEqual(try store.record(for: record.request.transactionID).journal.phase, .active)
    }

    func testInterruptedCatalogCommitCanRecoverBeforeSystemAppliedJournal() throws {
        let (record, hash) = try prepare()
        _ = try manager(record).apply(request: record.request, sourceTransactionURL: transaction(record))
        XCTAssertNil(try store.record(for: record.request.transactionID).journal.originalModernManifestSHA256)
        try restore(record, hash)
        XCTAssertNil(try store.activeOrPendingTransaction())
        XCTAssertEqual(prefs.writes, 0)
    }

    func testPreferenceSynchronizationFailureRetainsUndoForRecovery() throws {
        let (record, hash) = try prepare()
        _ = try manager(record).apply(request: record.request, sourceTransactionURL: transaction(record))
        prefs.synchronizes = false
        XCTAssertThrowsError(try activation.activate(request: record.request, transactionURL: transaction(record), backupSHA256: hash))
        prefs.synchronizes = true
        try restore(record, hash)
        XCTAssertNil(prefs.value(forKey: NativeLockGoldenGateActivation.pathKey))
        XCTAssertNil(prefs.value(forKey: NativeLockGoldenGateActivation.forceKey))
    }

    func testPriorThirdPartySelectionIsRecognizedButNotCopiedIntoActiveCatalog() throws {
        let foreignID = "99999999-9999-4999-8999-999999999999"
        func replace(_ value: Any) throws -> Any {
            if var d = value as? [String: Any] {
                if let configuration = d["Configuration"] as? Data,
                   let decoded = try PropertyListSerialization.propertyList(from: configuration, options: [], format: nil) as? [String: Any],
                   decoded["assetID"] != nil {
                    d["Configuration"] = try PropertyListSerialization.data(fromPropertyList: ["assetID": foreignID], format: .binary, options: 0)
                }
                for (key, child) in d { d[key] = try replace(child) }
                return d
            }
            if let a = value as? [Any] { return try a.map(replace) }
            return value
        }
        let originalIndex = try PropertyListSerialization.propertyList(from: Data(contentsOf: index), options: [], format: nil)
        try PropertyListSerialization.data(fromPropertyList: replace(originalIndex), format: .binary, options: 0).write(to: index)
        XCTAssertThrowsError(try activation.preflight())
        let cacheURL = wallpaper.appendingPathComponent("aerials/manifest/entries.json")
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var cache = try JSONSerialization.jsonObject(with: Data(contentsOf: bundled)) as! [String: Any]
        var asset = (cache["assets"] as! [[String: Any]])[0]
        asset["id"] = foreignID
        cache["assets"] = [asset]; cache["version"] = 1
        let cacheBytes = try JSONSerialization.data(withJSONObject: cache)
        try cacheBytes.write(to: cacheURL)
        try activation.preflight()
        let before = try Data(contentsOf: index)
        let (record, hash) = try apply()
        let target = try NativeLockSafetyInspector.aerialManifest(from: Data(contentsOf: activation.catalogURL(for: record.request)), schemaVersion: 2)
        XCTAssertFalse((target["assets"] as! [[String: Any]]).contains { $0["id"] as? String == foreignID })
        _ = try manager(record).inspectStore(requiredAssetID: record.request.assetID.uuidString)
        try restore(record, hash)
        XCTAssertEqual(try Data(contentsOf: cacheURL), cacheBytes)
        XCTAssertEqual(try Data(contentsOf: index), before)
    }

    func testMalformedPreviousCatalogFailsBeforePreferenceWrites() throws {
        let url = wallpaper.appendingPathComponent("aerials/manifest/entries.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a manifest".utf8).write(to: url)
        XCTAssertThrowsError(try activation.preflight())
        XCTAssertEqual(prefs.writes, 0)
    }

    func testPreparedActivationDigestCannotBeOverwritten() throws {
        let (record, _) = try prepare()
        XCTAssertThrowsError(try store.markAerialActivationPrepared(transactionID: record.request.transactionID,
                                                                  sha256: String(repeating: "0", count: 64)))
    }

    func testExternalPreferenceChangeBetweenPreparationAndActivationIsPreserved() throws {
        let (record, hash) = try prepare()
        _ = try manager(record).apply(request: record.request, sourceTransactionURL: transaction(record))
        prefs.values[NativeLockGoldenGateActivation.forceKey] = false
        XCTAssertThrowsError(try activation.activate(request: record.request, transactionURL: transaction(record), backupSHA256: hash))
        XCTAssertEqual(prefs.writes, 0)
        try restore(record, hash)
        XCTAssertEqual(prefs.value(forKey: NativeLockGoldenGateActivation.forceKey) as? Bool, false)
    }

    func testFailedRestoreSynchronizationMustSucceedBeforeRetryCompletes() throws {
        let (record, hash) = try apply()
        prefs.synchronizes = false
        XCTAssertThrowsError(try activation.restore(request: record.request, transactionURL: transaction(record), backupSHA256: hash))
        XCTAssertThrowsError(try activation.restore(request: record.request, transactionURL: transaction(record), backupSHA256: hash))
        prefs.synchronizes = true
        try restore(record, hash)
        XCTAssertNil(prefs.value(forKey: NativeLockGoldenGateActivation.pathKey))
    }

    func testMaintenanceRejectsRemovedOwnedAssetWithValidAppleSelectionWithoutWritingIndex() throws {
        let (record, _) = try apply()
        let url = activation.catalogURL(for: record.request)
        var catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        catalog["assets"] = (catalog["assets"] as! [[String: Any]]).filter { $0["id"] as? String != record.request.assetID.uuidString }
        try JSONSerialization.data(withJSONObject: catalog).write(to: url)
        // Simulate an external writer reverting Linked choices to a valid Apple asset.
        try Data(contentsOf: transaction(record).appendingPathComponent(NativeLockPaths.originalWallpaperIndexFilename)).write(to: index)
        let before = try Data(contentsOf: index)
        _ = try manager(record).inspectStore()
        XCTAssertThrowsError(try manager(record).inspectStore(requiredAssetID: record.request.assetID.uuidString))
        XCTAssertEqual(try Data(contentsOf: index), before)
    }

    func testPhotoOrMissingLinkedSelectionDoesNotBlockSelectiveCleanup() throws {
        for photo in [true, false] {
            let (record, hash) = try apply()
            let foreign: [String: Any] = photo
                ? ["SystemDefault": ["Type": "individual", "Desktop": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.image"]]]]], "Displays": [:], "Spaces": [:]]
                : ["SystemDefault": [:], "Displays": [:], "Spaces": [:]]
            let bytes = try PropertyListSerialization.data(fromPropertyList: foreign, format: .binary, options: 0)
            try bytes.write(to: index)
            try restore(record, hash)
            XCTAssertEqual(try Data(contentsOf: index), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: wallpaper.appendingPathComponent("aerials/videos/\(record.request.assetID).mov").path))
            // Restore the Aerial fixture before starting the next independent transaction.
            try Data(contentsOf: transaction(record).appendingPathComponent(NativeLockPaths.originalWallpaperIndexFilename)).write(to: index)
        }
    }
}
