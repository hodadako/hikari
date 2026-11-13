import Darwin
import XCTest
@testable import HikariNativeLock

/// All writes in this suite are confined to a unique temporary directory.
final class NativeLockGoldenGateTests: XCTestCase {
    private var root: URL!
    private var index: URL!
    private var manifest: URL!
    private var store: NativeLockUserTransactionStore!
    private var manager: NativeLockModernTransactionManager!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Hikari27-\(UUID())")
        index = root.appendingPathComponent("Wallpaper/Store/Index.plist")
        manifest = root.appendingPathComponent("Wallpaper/aerials/manifest/entries.json")
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let fixtures = try XCTUnwrap(bundle.url(forResource: "Fixtures", withExtension: nil))
            .appendingPathComponent("macOS27")
        for (source, destination) in [("Index.plist", index!), ("entries.json", manifest!)] {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(source), to: destination)
        }
        store = NativeLockUserTransactionStore(
            supportRootURL: root.appendingPathComponent("Support"), wallpaperIndexURL: index,
            userID: UInt32(getuid())
        )
        manager = NativeLockModernTransactionManager(environment: NativeLockModernEnvironment(
            wallpaperRootURL: root.appendingPathComponent("Wallpaper"), manifestURL: manifest,
            mediaDirectoryURL: root.appendingPathComponent("Wallpaper/aerials/videos"),
            previewDirectoryURL: root.appendingPathComponent("Wallpaper/aerials/thumbnails"),
            supportedOperatingSystemMajorVersions: [26, 27], operatingSystemMajorVersion: 27
        ))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testObservedGoldenGateContractIsReadOnly() throws {
        let before = try bytes()
        let snapshot = try manager.inspectStore()
        XCTAssertGreaterThan(snapshot.linkedChoiceCount, 2)
        XCTAssertEqual(try bytes(), before)
        XCTAssertEqual(snapshot.manifestSHA256, NativeLockDigest.sha256(of: before[1]))
    }

    func testGoldenGateApplyReopenAndRestorePreservesOriginalBytesAndBackups() throws {
        var indexBefore = try indexDictionary()
        var defaults = indexBefore["SystemDefault"] as! [String: Any]
        let originalLinked = defaults["Linked"] as! [String: Any]
        defaults["Desktop"] = originalLinked
        defaults["Idle"] = originalLinked
        indexBefore["SystemDefault"] = defaults
        try writeIndex(indexBefore)
        let original = try bytes()
        let record = try apply()
        XCTAssertEqual(record.journal.operatingSystemMajorVersion, 27)
        XCTAssertEqual(record.journal.phase, .active)
        XCTAssertTrue(try store.linkedWallpaperMappingMatches(transactionID: record.request.transactionID))
        let appliedDefaults = try XCTUnwrap(indexDictionary()["SystemDefault"] as? [String: Any])
        for key in ["Desktop", "Idle"] {
            XCTAssertTrue(NSDictionary(dictionary: appliedDefaults[key] as! [String: Any])
                .isEqual(to: originalLinked))
        }
        let reopened = NativeLockUserTransactionStore(
            supportRootURL: root.appendingPathComponent("Support"), wallpaperIndexURL: index,
            userID: UInt32(getuid())
        )
        XCTAssertEqual(try reopened.activeOrPendingTransaction()?.request.transactionID, record.request.transactionID)
        try restore(record)
        XCTAssertEqual(try bytes(), original)
        XCTAssertNil(try store.activeOrPendingTransaction())
        let transaction = store.transactionDirectoryURL(for: record.request.transactionID)
        XCTAssertEqual(try Data(contentsOf: transaction.appendingPathComponent(NativeLockPaths.originalWallpaperIndexFilename)), original[0])
        XCTAssertEqual(try Data(contentsOf: transaction.appendingPathComponent(NativeLockPaths.originalModernManifestFilename)), original[1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Wallpaper/aerials/videos/\(record.request.assetID).mov").path))
    }

    func testReplacementLeavesFirstJournalAndBackupReadable() throws {
        let original = try bytes()
        let first = try apply()
        try restore(first)
        let second = try apply()
        XCTAssertNotEqual(first.request.assetID, second.request.assetID)
        XCTAssertEqual(try store.record(for: first.request.transactionID).journal.phase, .restored)
        try restore(second)
        XCTAssertEqual(try bytes(), original)
    }

    func testUnknownProviderRejectedBeforeManifestOrMediaWrite() throws {
        var dictionary = try indexDictionary()
        var linked = try XCTUnwrap((dictionary["SystemDefault"] as? [String: Any])?["Linked"] as? [String: Any])
        var content = linked["Content"] as! [String: Any]
        var choices = content["Choices"] as! [[String: Any]]
        choices[0]["Provider"] = "unknown.wallpaper.provider"
        content["Choices"] = choices
        linked["Content"] = content
        var systemDefault = dictionary["SystemDefault"] as! [String: Any]
        systemDefault["Linked"] = linked
        dictionary["SystemDefault"] = systemDefault
        try writeIndex(dictionary)
        let record = try prepare()
        let before = try bytes()
        XCTAssertThrowsError(try manager.apply(request: record.request, sourceTransactionURL: transaction(record)))
        XCTAssertEqual(try bytes(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Wallpaper/aerials/videos").path))
    }

    func testMissingLinkedTopologyIsRejectedWithoutMaterialization() throws {
        try writeIndex(["SystemDefault": [:], "Displays": [:], "Spaces": [:]])
        let before = try bytes()
        XCTAssertThrowsError(try manager.inspectStore()) {
            XCTAssertEqual($0 as? NativeLockTransactionError, .noWallpaperChoices)
        }
        XCTAssertEqual(try bytes(), before)
    }

    func testUnknownSchemaAndBooleanVersionAreRejected() throws {
        for version: Any in [2, true] {
            var data = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
            data["version"] = version
            try JSONSerialization.data(withJSONObject: data).write(to: manifest)
            let before = try bytes()
            XCTAssertThrowsError(try manager.inspectStore())
            XCTAssertEqual(try bytes(), before)
        }
    }

    func testMalformedPlacementAndMissingManifestAssetFailClosed() throws {
        let original = try bytes()
        var dictionary = try indexDictionary()
        var defaults = dictionary["SystemDefault"] as! [String: Any]
        var linked = defaults["Linked"] as! [String: Any]
        var content = linked["Content"] as! [String: Any]
        content["EncodedOptionValues"] = "$null"
        linked["Content"] = content
        defaults["Linked"] = linked
        dictionary["SystemDefault"] = defaults
        try writeIndex(dictionary)
        XCTAssertThrowsError(try manager.inspectStore())
        try original[0].write(to: index)
        var catalog = try JSONSerialization.jsonObject(with: original[1]) as! [String: Any]
        catalog["assets"] = [[String: Any]]()
        try JSONSerialization.data(withJSONObject: catalog).write(to: manifest)
        XCTAssertThrowsError(try manager.inspectStore())
    }

    func testGoldenGateSafetyDistinguishesNewAndUpgradedTransactions() throws {
        let os = OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 1)
        XCTAssertEqual(NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: os, hasSelectedMedia: true,
            aerialManifestURL: manifest, aerialWallpaperIndexURL: index, goldenGateRuntimeValidated: true
        ).state, .ready)
        XCTAssertEqual(NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: os, hasSelectedMedia: false, transactionPhase: .active,
            transactionBackend: .userAerials, transactionOperatingSystemMajorVersion: 27,
            aerialManifestURL: manifest, aerialWallpaperIndexURL: index, goldenGateRuntimeValidated: true
        ).state, .active)
        for source: Int? in [nil, 26] {
            XCTAssertEqual(NativeLockSafetyInspector.evaluate(
                operatingSystemVersion: os, hasSelectedMedia: false, transactionPhase: .active,
                transactionBackend: .userAerials, transactionOperatingSystemMajorVersion: source,
                aerialManifestURL: manifest, aerialWallpaperIndexURL: index, goldenGateRuntimeValidated: true
            ).state, .recoveryRequired)
        }
    }

    func testCorruptManifestBackupFailsPreflightWithoutChangingJournalOrIndex() throws {
        let record = try apply()
        try Data("corrupt".utf8).write(to: transaction(record).appendingPathComponent(NativeLockPaths.originalModernManifestFilename))
        let before = try bytes()
        let saved = try store.record(for: record.request.transactionID)
        XCTAssertThrowsError(try manager.validateRestore(
            originalManifestSHA256: try XCTUnwrap(record.journal.originalModernManifestSHA256),
            sourceTransactionURL: transaction(record)
        ))
        XCTAssertEqual(try store.record(for: record.request.transactionID), saved)
        XCTAssertEqual(try bytes(), before)
    }

    func testCorruptIndexBackupFailsPreflightWithoutChangingJournalOrManifest() throws {
        let record = try apply()
        try Data("corrupt".utf8).write(to: transaction(record).appendingPathComponent(NativeLockPaths.originalWallpaperIndexFilename))
        let before = try bytes()
        let saved = try store.record(for: record.request.transactionID)
        XCTAssertThrowsError(try store.validateWallpaperRestore(transactionID: record.request.transactionID))
        XCTAssertEqual(try store.record(for: record.request.transactionID), saved)
        XCTAssertEqual(try bytes(), before)
    }

    func testStagedMediaFailureRollsBackNewCopiesAndKeepsRecoveryInputs() throws {
        let record = try prepare()
        try Data("tampered".utf8).write(to: transaction(record).appendingPathComponent(NativeLockPaths.stagedMediaFilename))
        let original = try bytes()
        XCTAssertThrowsError(try manager.apply(request: record.request, sourceTransactionURL: transaction(record)))
        try store.markRecoveryRequired(transactionID: record.request.transactionID, error: "staged media changed")
        let pending = try XCTUnwrap(store.activeOrPendingTransaction())
        XCTAssertEqual(pending.journal.phase, .recoveryRequired)
        XCTAssertEqual(pending.journal.operatingSystemMajorVersion, 27)
        try store.validateWallpaperRestore(transactionID: record.request.transactionID)
        try store.restoreWallpaperMapping(transactionID: record.request.transactionID)
        try store.markRestored(transactionID: record.request.transactionID)
        XCTAssertEqual(try bytes(), original)
    }

    func testUpgradeRestorePreservesExternalChoicesAndCurrentTopology() throws {
        let record = try apply(majorVersion: 26)
        let policy = NativeLockOperatingSystemPolicy(majorVersion: 27, goldenGateRuntimeValidated: true)
        XCTAssertFalse(policy.canModifyTransaction(backend: .userAerials, operatingSystemMajorVersion: 26))
        XCTAssertTrue(policy.requiresUpgradeRestore(backend: .userAerials, operatingSystemMajorVersion: 26))
        var current = try indexDictionary()
        current["FutureMetadata"] = "preserve"
        var displays = current["Displays"] as! [String: Any]
        displays["NEW-DISPLAY"] = current["SystemDefault"]
        current["Displays"] = displays
        try writeIndex(current)
        // Treat the exact current bytes as applied too: forceSelective must win
        // over a matching digest when restoring across the OS boundary.
        let journalURL = transaction(record).appendingPathComponent(NativeLockPaths.journalFilename)
        var journal = try JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as! [String: Any]
        journal.removeValue(forKey: "operatingSystemMajorVersion") // pre-0.5.1 journal
        journal["appliedWallpaperIndexSHA256"] = NativeLockDigest.sha256(of: try Data(contentsOf: index))
        try JSONSerialization.data(withJSONObject: journal).write(to: journalURL)
        let old = try store.record(for: record.request.transactionID)
        XCTAssertNil(old.journal.operatingSystemMajorVersion)
        try restore(old, selective: true)
        let restored = try indexDictionary()
        XCTAssertEqual(restored["FutureMetadata"] as? String, "preserve")
        XCTAssertNotNil((restored["Displays"] as? [String: Any])?["NEW-DISPLAY"])
        XCTAssertFalse(try store.linkedWallpaperMappingMatches(transactionID: record.request.transactionID))
    }

    func testGoldenGatePolicyDoesNotAdoptAnUpgradedOrUnknownJournal() {
        let policy = NativeLockOperatingSystemPolicy(majorVersion: 27, goldenGateRuntimeValidated: true)
        for sourceOS: Int? in [nil, 15, 26, 28] {
            XCTAssertFalse(policy.canModifyTransaction(backend: .userAerials, operatingSystemMajorVersion: sourceOS))
        }
        XCTAssertFalse(policy.requiresUpgradeRestore(backend: .systemCatalog, operatingSystemMajorVersion: 15))
        XCTAssertFalse(NativeLockOperatingSystemPolicy(majorVersion: 28).requiresUpgradeRestore(backend: .userAerials, operatingSystemMajorVersion: 26))
    }

    private func prepare(majorVersion: Int = 27) throws -> NativeLockTransactionRecord {
        let media = root.appendingPathComponent("source.mov")
        let preview = root.appendingPathComponent("source.png")
        try Data("fixture movie".utf8).write(to: media)
        try Data("fixture preview".utf8).write(to: preview)
        return try store.prepare(sourceContentID: UUID(), title: "Fixture", preparedMediaURL: media,
                                 preparedPreviewURL: preview, operatingSystemMajorVersion: majorVersion)
    }

    private func apply(majorVersion: Int = 27) throws -> NativeLockTransactionRecord {
        let prepared = try prepare(majorVersion: majorVersion)
        let result = try manager.apply(request: prepared.request, sourceTransactionURL: transaction(prepared))
        _ = try store.markSystemApplied(transactionID: prepared.request.transactionID,
            manifestSHA256: result.manifestSHA256, backend: .userAerials,
            originalModernManifestSHA256: result.originalManifestSHA256)
        return try store.applyLinkedWallpaperMapping(transactionID: prepared.request.transactionID)
    }

    private func restore(_ record: NativeLockTransactionRecord, selective: Bool = false) throws {
        let originalHash = try XCTUnwrap(record.journal.originalModernManifestSHA256)
        try manager.validateRestore(originalManifestSHA256: originalHash, sourceTransactionURL: transaction(record))
        try store.validateWallpaperRestore(transactionID: record.request.transactionID, forceSelective: selective)
        _ = try store.beginRestore(transactionID: record.request.transactionID)
        try store.restoreWallpaperMapping(transactionID: record.request.transactionID, forceSelective: selective)
        try manager.restore(request: record.request, sourceTransactionURL: transaction(record),
            originalManifestSHA256: originalHash, appliedManifestSHA256: record.journal.systemManifestAppliedSHA256,
            forceSelective: selective)
        try store.markRestored(transactionID: record.request.transactionID)
    }

    private func transaction(_ record: NativeLockTransactionRecord) -> URL {
        store.transactionDirectoryURL(for: record.request.transactionID)
    }

    private func bytes() throws -> [Data] { try [Data(contentsOf: index), Data(contentsOf: manifest)] }
    private func indexDictionary() throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: index), options: [], format: nil) as? [String: Any])
    }
    private func writeIndex(_ value: [String: Any]) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: index)
    }
}
