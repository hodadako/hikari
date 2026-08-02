import Foundation
import XCTest
@testable import LuminaCore

final class StoreTests: XCTestCase {
    private var temporaryURL: URL!

    override func setUpWithError() throws {
        temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LuminaTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
    }

    func testSharedContainerCreatesExpectedDirectories() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: container.mediaDirectoryURL.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: container.thumbnailsDirectoryURL.path)
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: container.desktopPostersDirectoryURL.path)
        )
    }

    func testSettingsRoundTrip() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        let store = SettingsStore(container: container)
        let selectedID = UUID()
        let expected = LuminaSettings(
            selectedContentID: selectedID,
            playbackPreference: .paused,
            scalingMode: .fit,
            isMuted: false,
            pauseOnBattery: true,
            launchAtLogin: true,
            lastKnownScreenSaverInstalled: true,
            appIconStyle: .purple,
            overrideSystemLockShortcut: true
        )

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testLegacySettingsDefaultToBlueIcon() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        let legacyJSON = """
        {
          "isMuted": true,
          "lastKnownScreenSaverInstalled": false,
          "launchAtLogin": false,
          "pauseOnBattery": false,
          "playbackPreference": "playing",
          "scalingMode": "fill"
        }
        """
        try Data(legacyJSON.utf8).write(to: container.settingsURL)

        XCTAssertEqual(
            SettingsStore(container: container).load().appIconStyle,
            .blue
        )
        XCTAssertFalse(
            SettingsStore(container: container).load().overrideSystemLockShortcut
        )
    }

    func testContentDeleteOnlyRemovesManagedCopy() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        let store = ContentStore(container: container)
        let content = LiveContent(
            title: "Ocean",
            relativePath: "Media/ocean.mp4",
            fileSize: 3,
            duration: 12,
            width: 1920,
            height: 1080,
            codec: "avc1",
            thumbnailRelativePath: "Thumbnails/ocean.jpg"
        )
        let originalURL = temporaryURL
            .deletingLastPathComponent()
            .appendingPathComponent("original-\(UUID().uuidString).mp4")
        try Data("original".utf8).write(to: originalURL)
        try Data("copy".utf8).write(to: container.mediaURL(for: content))
        if let thumbnailURL = container.thumbnailURL(for: content) {
            try Data("thumbnail".utf8).write(to: thumbnailURL)
        }
        try Data("poster".utf8).write(
            to: container.desktopPosterURL(for: content)
        )
        try store.save([content])

        let updated = try store.delete(content, from: [content])

        XCTAssertTrue(updated.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: container.mediaURL(for: content).path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: container.desktopPosterURL(for: content).path
            )
        )
        try? FileManager.default.removeItem(at: originalURL)
    }

    func testCorruptSettingsFallBackToDefaults() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        try Data("not json".utf8).write(to: container.settingsURL)
        XCTAssertEqual(SettingsStore(container: container).load(), LuminaSettings())
    }

    func testScreenSaverContentSynchronizationCopiesSelectedMediaAndSettings() async throws {
        let source = try SharedContainer(
            rootURL: temporaryURL.appendingPathComponent("source")
        )
        let destination = try SharedContainer(
            rootURL: temporaryURL.appendingPathComponent("destination")
        )
        let content = LiveContent(
            title: "Ocean",
            relativePath: "Media/ocean.mp4",
            fileSize: 5,
            duration: 12,
            width: 3840,
            height: 2160,
            codec: "avc1",
            thumbnailRelativePath: "Thumbnails/ocean.jpg"
        )
        try Data("video".utf8).write(to: source.mediaURL(for: content))
        if let thumbnailURL = source.thumbnailURL(for: content) {
            try Data("image".utf8).write(to: thumbnailURL)
        }
        let settings = LuminaSettings(
            selectedContentID: content.id,
            scalingMode: .fit
        )
        let synchronizer = ScreenSaverContentSynchronizer(
            sourceContainer: source,
            destinationContainer: destination
        )

        try await synchronizer.synchronize(
            content: content,
            settings: settings
        )

        XCTAssertEqual(
            try Data(contentsOf: destination.mediaURL(for: content)),
            Data("video".utf8)
        )
        let synchronizedContents = ContentStore(container: destination).load()
        XCTAssertEqual(synchronizedContents.count, 1)
        XCTAssertEqual(synchronizedContents.first?.id, content.id)
        XCTAssertEqual(synchronizedContents.first?.relativePath, content.relativePath)
        XCTAssertEqual(SettingsStore(container: destination).load(), settings)
    }
}
