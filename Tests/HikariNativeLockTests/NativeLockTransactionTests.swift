import Darwin
import Foundation
import XCTest
@testable import HikariNativeLock

final class NativeLockTransactionTests: XCTestCase {
    private var rootURL: URL!
    private var userSupportURL: URL!
    private var wallpaperIndexURL: URL!
    private var idleAssetsURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HikariNativeTests-\(UUID().uuidString)")
        userSupportURL = rootURL.appendingPathComponent("UserSupport")
        wallpaperIndexURL = rootURL.appendingPathComponent("Index.plist")
        idleAssetsURL = rootURL.appendingPathComponent("idleassetsd")
        try FileManager.default.createDirectory(
            at: userSupportURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: idleAssetsURL.appendingPathComponent("Customer/4KSDR240FPS"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: idleAssetsURL.appendingPathComponent("snapshots"),
            withIntermediateDirectories: true
        )
        try makeWallpaperIndex().write(to: wallpaperIndexURL)
        try makeManifest().write(
            to: idleAssetsURL.appendingPathComponent("Customer/entries.json")
        )
        try Data("cache".utf8).write(
            to: idleAssetsURL.appendingPathComponent("Aerial.sqlite")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testApplyAndRestoreRoundTrip() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let originalIndex = try Data(contentsOf: wallpaperIndexURL)
        let originalManifest = try Data(
            contentsOf: idleAssetsURL.appendingPathComponent("Customer/entries.json")
        )
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let manager = makeSystemManager()

        let result = try manager.apply(
            request: record.request,
            sourceTransactionURL: store.transactionDirectoryURL(
                for: record.request.transactionID
            )
        )
        _ = try store.markSystemApplied(
            transactionID: record.request.transactionID,
            manifestSHA256: result.manifestSHA256
        )
        _ = try store.applyWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertTrue(
            try store.wallpaperMappingMatches(
                transactionID: record.request.transactionID
            )
        )
        XCTAssertEqual(
            try mappedAssetID(in: Data(contentsOf: wallpaperIndexURL)),
            record.request.assetID.uuidString
        )
        XCTAssertTrue(
            try manifestContainsHikariAsset(record.request.assetID)
        )
        XCTAssertEqual(try nativeCategoryDisplayName(), "Hikari")
        XCTAssertNotNil(try manager.activeTransaction())

        _ = try store.beginRestore(transactionID: record.request.transactionID)
        try store.restoreWallpaperMapping(transactionID: record.request.transactionID)
        _ = try manager.restore(request: record.request)
        try store.markRestored(transactionID: record.request.transactionID)

        XCTAssertEqual(try Data(contentsOf: wallpaperIndexURL), originalIndex)
        XCTAssertEqual(
            try Data(
                contentsOf: idleAssetsURL.appendingPathComponent(
                    "Customer/entries.json"
                )
            ),
            originalManifest
        )
        XCTAssertNil(try manager.activeTransaction())
    }

    func testMappingVerificationDetectsAnOSReset() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let originalIndex = try Data(contentsOf: wallpaperIndexURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        _ = try store.applyWallpaperMapping(
            transactionID: record.request.transactionID
        )
        XCTAssertTrue(
            try store.wallpaperMappingMatches(
                transactionID: record.request.transactionID
            )
        )

        try originalIndex.write(to: wallpaperIndexURL, options: .atomic)

        XCTAssertFalse(
            try store.wallpaperMappingMatches(
                transactionID: record.request.transactionID
            )
        )
    }

    func testReconcileAppliesAndRestoresAChoiceFromANewDisplay() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        _ = try store.applyWallpaperMapping(
            transactionID: record.request.transactionID
        )
        try addDisplayChoice(assetID: "NEW-DISPLAY")

        let reconciled = try store.reconcileWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertEqual(reconciled.journal.requiresSelectiveWallpaperRestore, true)
        XCTAssertTrue(
            try store.wallpaperMappingMatches(
                transactionID: record.request.transactionID
            )
        )
        XCTAssertEqual(
            try allMappedAssetIDs(in: Data(contentsOf: wallpaperIndexURL)),
            [record.request.assetID.uuidString, record.request.assetID.uuidString]
        )

        try store.restoreWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertEqual(
            try allMappedAssetIDs(in: Data(contentsOf: wallpaperIndexURL)),
            ["NEW-DISPLAY", "ORIGINAL"]
        )
    }

    func testReconcilePreservesLatestExternalChoiceForRestore() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        _ = try store.applyWallpaperMapping(
            transactionID: record.request.transactionID
        )
        try replaceSystemDefaultChoice(assetID: "EXTERNAL-RESET")

        _ = try store.reconcileWallpaperMapping(
            transactionID: record.request.transactionID
        )
        try store.restoreWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertEqual(
            try allMappedAssetIDs(in: Data(contentsOf: wallpaperIndexURL)),
            ["EXTERNAL-RESET"]
        )
    }

    func testSelectiveRestoreSurvivesAgentTopologyNormalization() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        _ = try store.applyWallpaperMapping(
            transactionID: record.request.transactionID
        )
        try normalizeSystemDefaultLikeWallpaperAgent()

        try store.restoreWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertEqual(
            try mappedAssetIDs(in: Data(contentsOf: wallpaperIndexURL)),
            ["ORIGINAL", "ORIGINAL"]
        )
    }

    func testApplyRefreshesBackupAfterAnExternalPreApplyChange() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let changedIndex = try makeWallpaperIndex(assetID: "CHANGED-BEFORE-APPLY")
        try changedIndex.write(to: wallpaperIndexURL, options: .atomic)
        _ = try store.markSystemApplied(
            transactionID: record.request.transactionID,
            manifestSHA256: String(repeating: "a", count: 64)
        )

        _ = try store.applyWallpaperMapping(
            transactionID: record.request.transactionID
        )
        try store.restoreWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertEqual(try Data(contentsOf: wallpaperIndexURL), changedIndex)
    }

    func testRestoreRejectsAChangedUserBackup() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let backupURL = store.transactionDirectoryURL(
            for: record.request.transactionID
        ).appendingPathComponent(NativeLockPaths.originalWallpaperIndexFilename)
        try makeWallpaperIndex(assetID: "TAMPERED").write(
            to: backupURL,
            options: .atomic
        )

        XCTAssertThrowsError(
            try store.restoreWallpaperMapping(
                transactionID: record.request.transactionID
            )
        ) { error in
            XCTAssertEqual(error as? NativeLockTransactionError, .invalidHash)
        }
    }

    func testRestorePreservesExternalManifestChanges() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let manager = makeSystemManager()
        _ = try manager.apply(
            request: record.request,
            sourceTransactionURL: store.transactionDirectoryURL(
                for: record.request.transactionID
            )
        )

        let manifestURL = idleAssetsURL.appendingPathComponent(
            "Customer/entries.json"
        )
        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        var assets = manifest["assets"] as! [[String: Any]]
        assets.append(["id": "EXTERNAL", "categories": ["EXTERNAL"]])
        manifest["assets"] = assets
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)

        _ = try manager.restore(request: record.request)
        let restored = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        let restoredAssets = restored["assets"] as! [[String: Any]]
        XCTAssertTrue(restoredAssets.contains { $0["id"] as? String == "EXTERNAL" })
        XCTAssertFalse(
            restoredAssets.contains {
                $0["id"] as? String == record.request.assetID.uuidString
            }
        )
    }

    func testRestoreWithoutSystemJournalIsNoopWhenNothingWasApplied() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )

        let result = try makeSystemManager().restore(request: record.request)

        XCTAssertEqual(result.operation, "restore-noop")
    }

    func testRestoreWithoutSystemJournalRejectsOrphanedHikariEntries() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let manifestURL = idleAssetsURL.appendingPathComponent(
            "Customer/entries.json"
        )
        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        var categories = manifest["categories"] as! [[String: Any]]
        categories.append(["id": NativeLockSystemTransactionManager.categoryID])
        manifest["categories"] = categories
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)

        XCTAssertThrowsError(
            try makeSystemManager().restore(request: record.request)
        ) { error in
            XCTAssertEqual(
                error as? NativeLockTransactionError,
                .systemManifestChanged
            )
        }
    }

    func testRestoreRejectsOrphanedPredecessorCategory() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let manifestURL = idleAssetsURL.appendingPathComponent(
            "Customer/entries.json"
        )
        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        var categories = manifest["categories"] as! [[String: Any]]
        categories.append([
            "id": NativeLockSystemTransactionManager.predecessorCategoryID
        ])
        manifest["categories"] = categories
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)

        XCTAssertThrowsError(
            try makeSystemManager().restore(request: record.request)
        ) { error in
            XCTAssertEqual(
                error as? NativeLockTransactionError,
                .systemManifestChanged
            )
        }
    }

    func testRestoreSelectsPredecessorSystemJournalRoot() throws {
        let transactionID = UUID()
        let currentRoot = rootURL.appendingPathComponent("CurrentSystemSupport")
        let predecessorRoot = rootURL.appendingPathComponent(
            "PredecessorSystemSupport"
        )
        let journalURL = predecessorRoot
            .appendingPathComponent("Transactions", isDirectory: true)
            .appendingPathComponent(transactionID.uuidString, isDirectory: true)
            .appendingPathComponent("system-journal.json")
        try FileManager.default.createDirectory(
            at: journalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: journalURL)

        XCTAssertEqual(
            NativeLockPaths.systemSupportRootForRestore(
                transactionID: transactionID,
                currentRootURL: currentRoot,
                predecessorRootURL: predecessorRoot
            ),
            predecessorRoot
        )
    }

    func testFinishedJournalClearsAStaleUserActiveMarker() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        try store.markRestored(transactionID: record.request.transactionID)
        try JSONEncoder().encode([
            "transactionID": record.request.transactionID
        ]).write(to: store.activeTransactionURL)

        XCTAssertNil(try store.activeOrPendingTransaction())
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: store.activeTransactionURL.path
            )
        )
    }

    func testDiscardUnappliedTransactionRemovesOnlyLocalStaging() throws {
        let store = makeUserStore()
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let originalIndex = try Data(contentsOf: wallpaperIndexURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Unapplied legacy video",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )

        try store.discardUnappliedTransaction(
            transactionID: record.request.transactionID
        )

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: store.transactionDirectoryURL(
                for: record.request.transactionID
            ).path
        ))
        XCTAssertNil(try store.activeOrPendingTransaction())
        XCTAssertEqual(try Data(contentsOf: wallpaperIndexURL), originalIndex)
    }

    private func makeUserStore() -> NativeLockUserTransactionStore {
        NativeLockUserTransactionStore(
            supportRootURL: userSupportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
    }

    private func makeSystemManager() -> NativeLockSystemTransactionManager {
        let environment = NativeLockSystemEnvironment(
            systemSupportRootURL: rootURL.appendingPathComponent("SystemSupport"),
            manifestURL: idleAssetsURL.appendingPathComponent(
                "Customer/entries.json"
            ),
            mediaDirectoryURL: idleAssetsURL.appendingPathComponent(
                "Customer/4KSDR240FPS"
            ),
            previewDirectoryURL: idleAssetsURL.appendingPathComponent("snapshots"),
            cacheURLs: [idleAssetsURL.appendingPathComponent("Aerial.sqlite")],
            supportedOperatingSystemMajorVersions: [15],
            operatingSystemMajorVersion: 15,
            enforceRootOwnership: false
        )
        return NativeLockSystemTransactionManager(environment: environment)
    }

    private func makeWallpaperIndex(assetID: String = "ORIGINAL") throws -> Data {
        let originalConfiguration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
        let choice: [String: Any] = [
            "Configuration": originalConfiguration,
            "Files": [Any](),
            "Provider": "com.apple.wallpaper.choice.aerials"
        ]
        let linked: [String: Any] = [
            "Content": ["Choices": [choice], "Shuffle": "$null"],
            "LastSet": Date(timeIntervalSince1970: 0),
            "LastUse": Date(timeIntervalSince1970: 0)
        ]
        return try PropertyListSerialization.data(
            fromPropertyList: [
                "AllSpacesAndDisplays": "$null",
                "Displays": [String: Any](),
                "Spaces": [String: Any](),
                "SystemDefault": ["Linked": linked, "Type": "linked"]
            ],
            format: .binary,
            options: 0
        )
    }

    private func makeManifest() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "version": 1,
                "initialAssetCount": 0,
                "localizationVersion": "test",
                "assets": [["id": "ORIGINAL", "categories": ["ORIGINAL"]]],
                "categories": [["id": "ORIGINAL"]]
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func addDisplayChoice(assetID: String) throws {
        let data = try Data(contentsOf: wallpaperIndexURL)
        var root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as! [String: Any]
        var displays = root["Displays"] as! [String: Any]
        displays["NEW-DISPLAY-ID"] = [
            "Desktop": try choiceContainer(assetID: assetID),
            "Type": "individual"
        ]
        root["Displays"] = displays
        try writeWallpaperDictionary(root)
    }

    private func replaceSystemDefaultChoice(assetID: String) throws {
        let data = try Data(contentsOf: wallpaperIndexURL)
        var root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as! [String: Any]
        root["SystemDefault"] = [
            "Linked": try choiceContainer(assetID: assetID),
            "Type": "linked"
        ]
        try writeWallpaperDictionary(root)
    }

    private func choiceContainer(assetID: String) throws -> [String: Any] {
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID],
            format: .binary,
            options: 0
        )
        return [
            "Content": [
                "Choices": [[
                    "Configuration": configuration,
                    "Files": [Any](),
                    "Provider": "com.apple.wallpaper.choice.aerials"
                ]],
                "Shuffle": "$null"
            ],
            "LastSet": Date(timeIntervalSince1970: 1),
            "LastUse": Date(timeIntervalSince1970: 1)
        ]
    }

    private func writeWallpaperDictionary(_ root: [String: Any]) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try data.write(to: wallpaperIndexURL, options: .atomic)
    }

    private func allMappedAssetIDs(in data: Data) throws -> [String] {
        let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        var assetIDs: [String] = []
        try collectAssetIDs(in: root, into: &assetIDs)
        return assetIDs.sorted()
    }

    private func collectAssetIDs(in value: Any, into assetIDs: inout [String]) throws {
        if let dictionary = value as? [String: Any] {
            if let configuration = dictionary["Configuration"] as? Data,
               dictionary["Provider"] is String {
                let decoded = try PropertyListSerialization.propertyList(
                    from: configuration,
                    options: [],
                    format: nil
                ) as! [String: Any]
                if let assetID = decoded["assetID"] as? String {
                    assetIDs.append(assetID)
                }
                return
            }
            for child in dictionary.values {
                try collectAssetIDs(in: child, into: &assetIDs)
            }
        } else if let array = value as? [Any] {
            for child in array {
                try collectAssetIDs(in: child, into: &assetIDs)
            }
        }
    }

    private func mappedAssetID(in data: Data) throws -> String? {
        let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as! [String: Any]
        let systemDefault = root["SystemDefault"] as! [String: Any]
        let linked = systemDefault["Linked"] as! [String: Any]
        let content = linked["Content"] as! [String: Any]
        let choices = content["Choices"] as! [[String: Any]]
        let configuration = choices[0]["Configuration"] as! Data
        let decoded = try PropertyListSerialization.propertyList(
            from: configuration,
            options: [],
            format: nil
        ) as! [String: Any]
        return decoded["assetID"] as? String
    }

    private func normalizeSystemDefaultLikeWallpaperAgent() throws {
        let data = try Data(contentsOf: wallpaperIndexURL)
        var root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as! [String: Any]
        let systemDefault = root["SystemDefault"] as! [String: Any]
        let linked = systemDefault["Linked"] as! [String: Any]
        root["SystemDefault"] = [
            "Desktop": linked,
            "Idle": linked,
            "Type": "individual"
        ]
        let normalized = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: .binary,
            options: 0
        )
        try normalized.write(to: wallpaperIndexURL, options: .atomic)
    }

    private func mappedAssetIDs(in data: Data) throws -> [String] {
        let root = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as! [String: Any]
        let systemDefault = root["SystemDefault"] as! [String: Any]
        return try ["Desktop", "Idle"].map { key in
            let choiceContainer = systemDefault[key] as! [String: Any]
            let content = choiceContainer["Content"] as! [String: Any]
            let choices = content["Choices"] as! [[String: Any]]
            let configuration = choices[0]["Configuration"] as! Data
            let decoded = try PropertyListSerialization.propertyList(
                from: configuration,
                options: [],
                format: nil
            ) as! [String: Any]
            return decoded["assetID"] as! String
        }
    }

    private func manifestContainsHikariAsset(_ assetID: UUID) throws -> Bool {
        let data = try Data(
            contentsOf: idleAssetsURL.appendingPathComponent(
                "Customer/entries.json"
            )
        )
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let assets = root["assets"] as! [[String: Any]]
        return assets.contains { $0["id"] as? String == assetID.uuidString }
    }

    // MARK: - Error model

    func testAerialCatalogMissingErrorHasUsefulDescription() {
        let error = NativeLockTransactionError.aerialCatalogMissing
        XCTAssertEqual(error.errorDescription, "Initialize Apple Aerial wallpapers first.")
    }

    func testLegacyTransactionUnsupportedOnCurrentOSErrorHasUsefulDescription() {
        let error = NativeLockTransactionError
            .legacyTransactionUnsupportedOnCurrentOperatingSystem(26)
        XCTAssertTrue(
            error.errorDescription?.contains("26") == true,
            "Error description should mention the OS version"
        )
    }

    func testUnsupportedOperatingSystemErrorMentionsVersion() {
        let error = NativeLockTransactionError.unsupportedOperatingSystem(26)
        XCTAssertTrue(
            error.errorDescription?.contains("26") == true,
            "Error description should mention the OS version"
        )
    }

    private func nativeCategoryDisplayName() throws -> String? {
        let data = try Data(
            contentsOf: idleAssetsURL.appendingPathComponent(
                "Customer/entries.json"
            )
        )
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let categories = root["categories"] as! [[String: Any]]
        return categories.first {
            $0["id"] as? String == NativeLockSystemTransactionManager.categoryID
        }?["localizedNameKey"] as? String
    }
}
