import Darwin
import Foundation
import XCTest
@testable import HikariNativeLock

final class NativeLockModernTransactionTests: XCTestCase {
    private var rootURL: URL!
    private var supportURL: URL!
    private var wallpaperRootURL: URL!
    private var manifestURL: URL!
    private var wallpaperIndexURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HikariModernTests-\(UUID().uuidString)")
        supportURL = rootURL.appendingPathComponent("Support")
        wallpaperRootURL = rootURL.appendingPathComponent("Wallpaper")
        manifestURL = wallpaperRootURL
            .appendingPathComponent("aerials/manifest/entries.json")
        wallpaperIndexURL = wallpaperRootURL.appendingPathComponent("Store/Index.plist")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: wallpaperIndexURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try makeManifest().write(to: manifestURL)
        try makeIndex().write(to: wallpaperIndexURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    /// Exercises a fixture through macOS 26 Apply, an unreviewed OS write refusal and
    /// schema-change refusal, then verifies byte-for-byte Restore on macOS 26.
    func testModernApplyTargetsOnlyLinkedChoicesAndRestoresByteForByte() throws {
        let store = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
        let mediaURL = rootURL.appendingPathComponent("source.mov")
        let previewURL = rootURL.appendingPathComponent("source.png")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let originalIndex = try Data(contentsOf: wallpaperIndexURL)
        let originalManifest = try Data(contentsOf: manifestURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )

        let manager = NativeLockModernTransactionManager(environment: environment())
        let result = try manager.apply(
            request: record.request,
            sourceTransactionURL: store.transactionDirectoryURL(
                for: record.request.transactionID
            )
        )
        _ = try store.markSystemApplied(
            transactionID: record.request.transactionID,
            manifestSHA256: result.manifestSHA256,
            backend: .userAerials,
            originalModernManifestSHA256: result.originalManifestSHA256
        )
        _ = try store.applyLinkedWallpaperMapping(
            transactionID: record.request.transactionID
        )

        XCTAssertTrue(
            try store.linkedWallpaperMappingMatches(
                transactionID: record.request.transactionID
            )
        )
        let encodedOptions = try XCTUnwrap(
            encodedOptionValues(path: ["SystemDefault", "Linked"])
        )
        let decodedOptions = try PropertyListSerialization.propertyList(
            from: encodedOptions,
            options: [],
            format: nil
        ) as! [String: Any]
        let placement = decodedOptions["values"] as! [String: Any]
        let picker = placement["placement"] as! [String: Any]
        let pickerValues = picker["picker"] as! [String: Any]
        let selectedPlacement = pickerValues["_0"] as! [String: Any]
        XCTAssertEqual(selectedPlacement["id"] as? String, "FillScreen")
        XCTAssertEqual(
            try choiceAssetID(path: ["SystemDefault", "Linked"]),
            record.request.assetID.uuidString
        )
        XCTAssertEqual(
            try choiceAssetID(path: ["Displays", "DISPLAY", "Desktop"]),
            "DESKTOP"
        )
        XCTAssertEqual(
            try choiceAssetID(path: ["Displays", "DISPLAY", "Idle"]),
            "IDLE"
        )
        XCTAssertTrue(try manifestContainsAsset(record.request.assetID.uuidString))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: wallpaperRootURL
                    .appendingPathComponent(
                        "aerials/videos/\(record.request.assetID.uuidString).mov"
                    ).path
            )
        )

        // Reopen the same files as if the Mac had upgraded with an active transaction.
        let upgradedStore = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
        let savedRecord = try XCTUnwrap(
            upgradedStore.activeOrPendingTransaction(removeStaleMarker: false)
        )
        XCTAssertEqual(savedRecord.journal.phase, .active)
        XCTAssertEqual(savedRecord.journal.backend, .userAerials)
        let transactionURL = store.transactionDirectoryURL(for: record.request.transactionID)
        let mediaCopyURL = wallpaperRootURL.appendingPathComponent(
            "aerials/videos/\(record.request.assetID.uuidString).mov"
        )
        let previewCopyURL = wallpaperRootURL.appendingPathComponent(
            "aerials/thumbnails/\(record.request.assetID.uuidString).png"
        )
        let watchedURLs = [
            wallpaperIndexURL!, manifestURL!, store.activeTransactionURL, mediaCopyURL, previewCopyURL
        ] + (try FileManager.default.contentsOfDirectory(
            at: transactionURL,
            includingPropertiesForKeys: nil
        ))
        let snapshots = try watchedURLs.map { try Data(contentsOf: $0) }
        let futureManager = NativeLockModernTransactionManager(environment: environment(majorVersion: 28))
        XCTAssertThrowsError(try futureManager.apply(
            request: savedRecord.request,
            sourceTransactionURL: transactionURL
        )) {
            XCTAssertEqual($0 as? NativeLockTransactionError, .unsupportedOperatingSystem(28))
        }
        XCTAssertThrowsError(try futureManager.restore(
            request: savedRecord.request,
            sourceTransactionURL: transactionURL,
            originalManifestSHA256: result.originalManifestSHA256,
            appliedManifestSHA256: result.manifestSHA256
        )) {
            XCTAssertEqual($0 as? NativeLockTransactionError, .unsupportedOperatingSystem(28))
        }
        XCTAssertEqual(try watchedURLs.map { try Data(contentsOf: $0) }, snapshots)

        // A schema revision must also prevent selective restore on a supported OS.
        let appliedManifest = try Data(contentsOf: manifestURL)
        var newerManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: appliedManifest) as? [String: Any]
        )
        newerManifest["version"] = 2
        let newerManifestData = try JSONSerialization.data(withJSONObject: newerManifest)
        try newerManifestData.write(to: manifestURL)
        XCTAssertThrowsError(try manager.restore(
            request: savedRecord.request,
            sourceTransactionURL: transactionURL,
            originalManifestSHA256: result.originalManifestSHA256,
            appliedManifestSHA256: result.manifestSHA256
        )) {
            XCTAssertEqual($0 as? NativeLockTransactionError, .invalidWallpaperStore)
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), newerManifestData)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mediaCopyURL.path))
        try appliedManifest.write(to: manifestURL)

        _ = try store.beginRestore(transactionID: record.request.transactionID)
        try store.restoreWallpaperMapping(transactionID: record.request.transactionID)
        try manager.restore(
            request: record.request,
            sourceTransactionURL: store.transactionDirectoryURL(
                for: record.request.transactionID
            ),
            originalManifestSHA256: result.originalManifestSHA256,
            appliedManifestSHA256: result.manifestSHA256
        )
        try store.markRestored(transactionID: record.request.transactionID)

        XCTAssertEqual(try Data(contentsOf: wallpaperIndexURL), originalIndex)
        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifest)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: wallpaperRootURL
                    .appendingPathComponent(
                        "aerials/videos/\(record.request.assetID.uuidString).mov"
                    ).path
            )
        )
    }

    func testLinkedWallpaperChoicePreflightRequiresAppleMaterializedChoice() throws {
        let store = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )

        XCTAssertTrue(try store.hasLinkedWallpaperChoices())

        try makeIndex(includeLinkedChoices: false).write(to: wallpaperIndexURL)

        XCTAssertFalse(try store.hasLinkedWallpaperChoices())
    }

    func testMaterializeLinkedTopologyRestoresOriginalDesktopAndIdleBytes() throws {
        try makeIndex(includeLinkedChoices: false).write(to: wallpaperIndexURL)
        let originalIndex = try Data(contentsOf: wallpaperIndexURL)
        let mediaURL = rootURL.appendingPathComponent("source.mov")
        let previewURL = rootURL.appendingPathComponent("source.png")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)

        let store = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
        let prepared = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let materialized = try store.materializeLinkedWallpaperTopology(
            transactionID: prepared.request.transactionID,
            assetID: "3B2922AA-19BD-4D54-B43E-B45EE5DFA56E",
            topology: NativeLockLinkedWallpaperTopology(
                spaceIDs: ["SPACE-1", "SPACE-2"],
                displayIDs: ["DISPLAY-1"]
            )
        )

        XCTAssertEqual(materialized.journal.backend, .userAerials)
        XCTAssertNotNil(materialized.journal.materializedWallpaperIndexSHA256)
        XCTAssertTrue(try store.hasLinkedWallpaperChoices())

        _ = try store.beginRestore(transactionID: prepared.request.transactionID)
        try store.restoreWallpaperMapping(transactionID: prepared.request.transactionID)

        XCTAssertEqual(try Data(contentsOf: wallpaperIndexURL), originalIndex)
    }

    func testUpgradeSelectiveRestoreRemovesBootstrapLinkedWithoutInventingFallback() throws {
        try makeIndex(includeLinkedChoices: false).write(to: wallpaperIndexURL)
        let original = try PropertyListSerialization.propertyList(from: Data(contentsOf: wallpaperIndexURL), options: [], format: nil) as! [String: Any]
        let store = NativeLockUserTransactionStore(supportRootURL: supportURL, wallpaperIndexURL: wallpaperIndexURL, userID: UInt32(getuid()))
        let media = rootURL.appendingPathComponent("source.mov"), preview = rootURL.appendingPathComponent("source.png")
        try Data("movie".utf8).write(to: media); try Data("preview".utf8).write(to: preview)
        let record = try store.prepare(sourceContentID: UUID(), title: "Bootstrap", preparedMediaURL: media,
                                       preparedPreviewURL: preview, operatingSystemMajorVersion: 26)
        _ = try store.materializeLinkedWallpaperTopology(transactionID: record.request.transactionID,
            assetID: "11111111-1111-4111-8111-111111111111",
            topology: NativeLockLinkedWallpaperTopology(spaceIDs: ["SPACE-1"], displayIDs: ["DISPLAY-1"]))
        _ = try store.markSystemApplied(transactionID: record.request.transactionID,
            manifestSHA256: String(repeating: "0", count: 64), backend: .userAerials)
        _ = try store.applyLinkedWallpaperMapping(transactionID: record.request.transactionID)
        var current = try PropertyListSerialization.propertyList(from: Data(contentsOf: wallpaperIndexURL), options: [], format: nil) as! [String: Any]
        current["ExternalMetadata"] = "preserve"
        current["Type"] = "linked" // root Type was not written by bootstrap
        var displays = current["Displays"] as! [String: Any]
        displays["EXTERNAL-DISPLAY"] = original["SystemDefault"]
        current["Displays"] = displays
        try PropertyListSerialization.data(fromPropertyList: current, format: .binary, options: 0).write(to: wallpaperIndexURL)
        try store.validateWallpaperRestore(transactionID: record.request.transactionID, forceSelective: true)
        try store.restoreWallpaperMapping(transactionID: record.request.transactionID, forceSelective: true)
        let restored = try PropertyListSerialization.propertyList(from: Data(contentsOf: wallpaperIndexURL), options: [], format: nil) as! [String: Any]
        XCTAssertEqual(restored["ExternalMetadata"] as? String, "preserve")
        XCTAssertEqual(restored["Type"] as? String, "linked")
        let restoredDisplays = restored["Displays"] as! [String: Any]
        XCTAssertNotNil(restoredDisplays["DISPLAY-1"])
        XCTAssertTrue(NSDictionary(dictionary: restoredDisplays["EXTERNAL-DISPLAY"] as! [String: Any]).isEqual(to: original["SystemDefault"] as! [String: Any]))
        XCTAssertFalse(try store.hasLinkedWallpaperChoices())
        let defaults = restored["SystemDefault"] as! [String: Any]
        let oldDefaults = original["SystemDefault"] as! [String: Any]
        for key in ["Desktop", "Idle"] {
            XCTAssertTrue(NSDictionary(dictionary: defaults[key] as! [String: Any]).isEqual(to: oldDefaults[key] as! [String: Any]))
        }
    }

    func testApplyThrowsAerialCatalogMissingWhenManifestAbsent() throws {
        // Remove the manifest to simulate an uninitialized Aerial catalog.
        try FileManager.default.removeItem(at: manifestURL)

        let store = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
        let mediaURL = rootURL.appendingPathComponent("source.mov")
        let previewURL = rootURL.appendingPathComponent("source.png")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )

        let manager = NativeLockModernTransactionManager(environment: environment())
        XCTAssertThrowsError(
            try manager.apply(
                request: record.request,
                sourceTransactionURL: store.transactionDirectoryURL(
                    for: record.request.transactionID
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeLockTransactionError,
                .aerialCatalogMissing,
                "Expected aerialCatalogMissing but got \(error)"
            )
        }
    }

    /// Verifies a staged-media hash failure preserves fixture backups and live bytes.
    func testApplyWithChangedStagedMediaKeepsRollbackInputs() throws {
        let store = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
        let mediaURL = rootURL.appendingPathComponent("source.mov")
        let previewURL = rootURL.appendingPathComponent("source.png")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let transactionID = record.request.transactionID
        let savedRecord = try store.record(for: transactionID)
        let transactionURL = store.transactionDirectoryURL(for: transactionID)
        let originalManifest = try Data(contentsOf: manifestURL)
        let originalIndex = try Data(contentsOf: wallpaperIndexURL)
        try Data("changed media".utf8).write(to: transactionURL.appendingPathComponent(
            NativeLockPaths.stagedMediaFilename
        ))

        let environment = environment()
        let manager = NativeLockModernTransactionManager(environment: environment)
        XCTAssertThrowsError(try manager.apply(
            request: record.request,
            sourceTransactionURL: transactionURL
        )) {
            XCTAssertEqual($0 as? NativeLockTransactionError, .sourceHashMismatch)
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifest)
        XCTAssertEqual(try Data(contentsOf: wallpaperIndexURL), originalIndex)
        XCTAssertEqual(try store.record(for: transactionID), savedRecord)
        XCTAssertEqual(try Data(contentsOf: transactionURL.appendingPathComponent(
            NativeLockPaths.originalModernManifestFilename
        )), originalManifest)
        for directory in [environment.mediaDirectoryURL, environment.previewDirectoryURL] {
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testRestorePreservesHikariCategoryForAnotherAsset() throws {
        let store = NativeLockUserTransactionStore(
            supportRootURL: supportURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
        let mediaURL = rootURL.appendingPathComponent("source.mov")
        let previewURL = rootURL.appendingPathComponent("source.png")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)
        let record = try store.prepare(
            sourceContentID: UUID(),
            title: "Test Movie",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        let manager = NativeLockModernTransactionManager(environment: environment())
        let result = try manager.apply(
            request: record.request,
            sourceTransactionURL: store.transactionDirectoryURL(
                for: record.request.transactionID
            )
        )

        var manifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        var assets = manifest["assets"] as! [[String: Any]]
        assets.append([
            "id": "EXTERNAL-HIKARI-ASSET",
            "categories": [NativeLockModernTransactionManager.categoryID],
            "subcategories": [NativeLockModernTransactionManager.subcategoryID]
        ])
        manifest["assets"] = assets
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: manifestURL)

        try manager.restore(
            request: record.request,
            sourceTransactionURL: store.transactionDirectoryURL(
                for: record.request.transactionID
            ),
            originalManifestSHA256: result.originalManifestSHA256,
            appliedManifestSHA256: result.manifestSHA256
        )

        let restored = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        let restoredAssets = restored["assets"] as! [[String: Any]]
        let restoredCategories = restored["categories"] as! [[String: Any]]
        XCTAssertFalse(
            restoredAssets.contains { $0["id"] as? String == record.request.assetID.uuidString }
        )
        XCTAssertTrue(
            restoredAssets.contains { $0["id"] as? String == "EXTERNAL-HIKARI-ASSET" }
        )
        XCTAssertTrue(
            restoredCategories.contains {
                $0["id"] as? String == NativeLockModernTransactionManager.categoryID
            }
        )
    }

    /// Builds a simulated runtime using only this test's temporary wallpaper paths.
    private func environment(majorVersion: Int = 26) -> NativeLockModernEnvironment {
        NativeLockModernEnvironment(
            wallpaperRootURL: wallpaperRootURL,
            manifestURL: manifestURL,
            mediaDirectoryURL: wallpaperRootURL.appendingPathComponent("aerials/videos"),
            previewDirectoryURL: wallpaperRootURL.appendingPathComponent("aerials/thumbnails"),
            supportedOperatingSystemMajorVersions: [26],
            operatingSystemMajorVersion: majorVersion
        )
    }

    private func makeManifest() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "version": 1,
                "initialAssetCount": 1,
                "localizationVersion": "test",
                "assets": [["id": "APPLE", "categories": ["APPLE"]]],
                "categories": [["id": "APPLE", "representativeAssetID": "APPLE"]]
            ],
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func makeIndex(includeLinkedChoices: Bool = true) throws -> Data {
        var systemDefault: [String: Any] = [
            "Desktop": try choiceContainer(assetID: "DESKTOP"),
            "Idle": try choiceContainer(assetID: "IDLE")
        ]
        var display: [String: Any] = [
            "Desktop": try choiceContainer(assetID: "DESKTOP"),
            "Idle": try choiceContainer(assetID: "IDLE")
        ]
        if includeLinkedChoices {
            systemDefault["Linked"] = try choiceContainer(assetID: "ORIGINAL")
            display["Linked"] = try choiceContainer(assetID: "ORIGINAL")
        }
        return try PropertyListSerialization.data(
            fromPropertyList: [
                "AllSpacesAndDisplays": "$null",
                "SystemDefault": systemDefault,
                "Displays": [
                    "DISPLAY": display
                ],
                "Spaces": [String: Any]()
            ],
            format: .binary,
            options: 0
        )
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
            "LastSet": Date(timeIntervalSince1970: 0),
            "LastUse": Date(timeIntervalSince1970: 0)
        ]
    }

    private func choiceAssetID(path: [String]) throws -> String? {
        var value = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: wallpaperIndexURL),
            options: [],
            format: nil
        ) as! [String: Any]
        for key in path {
            value = value[key] as! [String: Any]
        }
        let content = value["Content"] as! [String: Any]
        let choice = (content["Choices"] as! [[String: Any]])[0]
        let configuration = choice["Configuration"] as! Data
        let decoded = try PropertyListSerialization.propertyList(
            from: configuration,
            options: [],
            format: nil
        ) as! [String: Any]
        return decoded["assetID"] as? String
    }

    private func encodedOptionValues(path: [String]) throws -> Data? {
        var value = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: wallpaperIndexURL),
            options: [],
            format: nil
        ) as! [String: Any]
        for key in path {
            value = value[key] as! [String: Any]
        }
        let content = value["Content"] as! [String: Any]
        return content["EncodedOptionValues"] as? Data
    }

    private func manifestContainsAsset(_ assetID: String) throws -> Bool {
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        let assets = root["assets"] as! [[String: Any]]
        return assets.contains { $0["id"] as? String == assetID }
    }
}
