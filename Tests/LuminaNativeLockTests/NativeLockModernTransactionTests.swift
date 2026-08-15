import Darwin
import Foundation
import XCTest
@testable import LuminaNativeLock

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

    private func environment() -> NativeLockModernEnvironment {
        NativeLockModernEnvironment(
            wallpaperRootURL: wallpaperRootURL,
            manifestURL: manifestURL,
            mediaDirectoryURL: wallpaperRootURL.appendingPathComponent("aerials/videos"),
            previewDirectoryURL: wallpaperRootURL.appendingPathComponent("aerials/thumbnails"),
            supportedOperatingSystemMajorVersions: [26],
            operatingSystemMajorVersion: 26
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

    private func makeIndex() throws -> Data {
        try PropertyListSerialization.data(
            fromPropertyList: [
                "AllSpacesAndDisplays": "$null",
                "SystemDefault": ["Linked": try choiceContainer(assetID: "ORIGINAL")],
                "Displays": [
                    "DISPLAY": [
                        "Linked": try choiceContainer(assetID: "ORIGINAL"),
                        "Desktop": try choiceContainer(assetID: "DESKTOP"),
                        "Idle": try choiceContainer(assetID: "IDLE")
                    ]
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

    private func manifestContainsAsset(_ assetID: String) throws -> Bool {
        let root = try JSONSerialization.jsonObject(
            with: Data(contentsOf: manifestURL)
        ) as! [String: Any]
        let assets = root["assets"] as! [[String: Any]]
        return assets.contains { $0["id"] as? String == assetID }
    }
}
