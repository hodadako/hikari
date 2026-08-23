import Darwin
import Foundation
import XCTest
@testable import LuminaNativeLock

final class NativeStorageMigrationTests: XCTestCase {
    private var rootURL: URL!
    private var canonicalRootURL: URL!
    private var legacyRootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HikariStorageMigration-\(UUID().uuidString)")
        canonicalRootURL = rootURL.appendingPathComponent("Lumina")
        legacyRootURL = rootURL.appendingPathComponent("LuminaNative")
        try FileManager.default.createDirectory(
            at: canonicalRootURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyRootURL.appendingPathComponent("Media"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyRootURL.appendingPathComponent("Thumbnails"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func testMergesLegacyLibraryAndArchivesOriginalRoot() throws {
        let legacyID = UUID()
        let canonicalID = UUID()
        try Data("legacy movie".utf8).write(
            to: legacyRootURL.appendingPathComponent("Media/legacy.mov")
        )
        try Data("legacy preview".utf8).write(
            to: legacyRootURL.appendingPathComponent("Thumbnails/legacy.jpg")
        )
        try Data("settings".utf8).write(
            to: legacyRootURL.appendingPathComponent("settings.json")
        )
        try writeContents(
            [
                makeContent(
                    id: legacyID,
                    relativePath: "Media/legacy.mov",
                    thumbnailRelativePath: "Thumbnails/legacy.jpg"
                )
            ],
            to: legacyRootURL.appendingPathComponent("contents.json")
        )
        try writeContents(
            [
                makeContent(
                    id: canonicalID,
                    relativePath: "Media/current.mov",
                    thumbnailRelativePath: nil
                )
            ],
            to: canonicalRootURL.appendingPathComponent("contents.json")
        )
        try FileManager.default.createDirectory(
            at: canonicalRootURL.appendingPathComponent("Media"),
            withIntermediateDirectories: true
        )
        try Data("current movie".utf8).write(
            to: canonicalRootURL.appendingPathComponent("Media/current.mov")
        )

        let report = try NativeStorageMigration.migrate(
            canonicalRootURL: canonicalRootURL,
            legacyRootURL: legacyRootURL,
            userID: UInt32(getuid())
        )

        XCTAssertTrue(report.didMigrate)
        XCTAssertEqual(report.migratedContentCount, 1)
        XCTAssertFalse(report.requiresRestore)
        XCTAssertNotNil(report.archivedLegacyRootURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyRootURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: report.archivedLegacyRootURL!.path
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: canonicalRootURL.appendingPathComponent("settings.json")),
            Data("settings".utf8)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: canonicalRootURL.appendingPathComponent("Media/legacy.mov").path
            )
        )

        let merged = try JSONSerialization.jsonObject(
            with: Data(
                contentsOf: canonicalRootURL.appendingPathComponent("contents.json")
            )
        ) as! [[String: Any]]
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged.contains { ($0["id"] as? String) == legacyID.uuidString })

        let secondReport = try NativeStorageMigration.migrate(
            canonicalRootURL: canonicalRootURL,
            legacyRootURL: legacyRootURL,
            userID: UInt32(getuid())
        )
        XCTAssertEqual(secondReport, report)
    }

    func testCopiesPendingNativeLockTransactionAndRequiresRestore() throws {
        let indexURL = legacyRootURL.appendingPathComponent("Index.plist")
        let indexData = try PropertyListSerialization.data(
            fromPropertyList: ["SystemDefault": []],
            format: .binary,
            options: 0
        )
        try indexData.write(to: indexURL)
        let mediaURL = rootURL.appendingPathComponent("prepared.mov")
        let previewURL = rootURL.appendingPathComponent("preview.jpg")
        try Data("movie".utf8).write(to: mediaURL)
        try Data("preview".utf8).write(to: previewURL)

        let legacyStore = NativeLockUserTransactionStore(
            supportRootURL: legacyRootURL,
            wallpaperIndexURL: indexURL,
            userID: UInt32(getuid())
        )
        let prepared = try legacyStore.prepare(
            sourceContentID: UUID(),
            title: "Pending video",
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )

        let report = try NativeStorageMigration.migrate(
            canonicalRootURL: canonicalRootURL,
            legacyRootURL: legacyRootURL,
            userID: UInt32(getuid())
        )

        XCTAssertEqual(report.migratedTransactionCount, 1)
        XCTAssertTrue(report.requiresRestore)
        let canonicalStore = NativeLockUserTransactionStore(
            supportRootURL: canonicalRootURL,
            wallpaperIndexURL: canonicalRootURL.appendingPathComponent(
                "Index.plist"
            ),
            userID: UInt32(getuid())
        )
        let migrated = try XCTUnwrap(
            try canonicalStore.activeOrPendingTransaction()
        )
        XCTAssertEqual(migrated.request.transactionID, prepared.request.transactionID)
        XCTAssertEqual(migrated.journal.phase, .prepared)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: canonicalRootURL.appendingPathComponent("Index.plist").path
            )
        )
    }

    private func makeContent(
        id: UUID,
        relativePath: String,
        thumbnailRelativePath: String?
    ) -> [String: Any] {
        var content: [String: Any] = [
            "id": id.uuidString,
            "title": "Video",
            "relativePath": relativePath,
            "fileSize": 12,
            "duration": 1.5,
            "width": 1920,
            "height": 1080,
            "codec": "h264",
            "createdAt": "2026-08-24T00:00:00Z"
        ]
        if let thumbnailRelativePath {
            content["thumbnailRelativePath"] = thumbnailRelativePath
        } else {
            content["thumbnailRelativePath"] = NSNull()
        }
        return content
    }

    private func writeContents(
        _ contents: [[String: Any]],
        to url: URL
    ) throws {
        let data = try JSONSerialization.data(
            withJSONObject: contents,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }
}
