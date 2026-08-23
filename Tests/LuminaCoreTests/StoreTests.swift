import CoreGraphics
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
        XCTAssertEqual(
            container.customAppIconURL.lastPathComponent,
            "CustomAppIcon.png"
        )
        XCTAssertEqual(
            container.customMenuBarIconURL.lastPathComponent,
            "CustomMenuBarIcon.png"
        )
    }

    func testCustomIconCanvasUsesAspectFillForLandscapeAndPortraitSources() {
        let landscape = IconGeometry.aspectFillSourceRect(
            sourceSize: CGSize(width: 1920, height: 1080),
            targetSize: IconGeometry.canvasSize
        )
        XCTAssertEqual(landscape.origin.x, 420, accuracy: 0.001)
        XCTAssertEqual(landscape.origin.y, 0, accuracy: 0.001)
        XCTAssertEqual(landscape.width, 1080, accuracy: 0.001)
        XCTAssertEqual(landscape.height, 1080, accuracy: 0.001)

        let portrait = IconGeometry.aspectFillSourceRect(
            sourceSize: CGSize(width: 1080, height: 1920),
            targetSize: IconGeometry.canvasSize
        )
        XCTAssertEqual(portrait.origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(portrait.origin.y, 420, accuracy: 0.001)
        XCTAssertEqual(portrait.width, 1080, accuracy: 0.001)
        XCTAssertEqual(portrait.height, 1080, accuracy: 0.001)

        let square = IconGeometry.aspectFillSourceRect(
            sourceSize: IconGeometry.canvasSize,
            targetSize: IconGeometry.canvasSize
        )
        XCTAssertEqual(square, CGRect(origin: .zero, size: IconGeometry.canvasSize))
    }

    func testIconFrameMatchesAppleLikeInsetAndKeepsCanvasSquare() {
        XCTAssertEqual(IconGeometry.iconFrame, CGRect(x: 72, y: 72, width: 880, height: 880))
        XCTAssertEqual(IconGeometry.cornerRadius, 193.6, accuracy: 0.001)
    }

    func testMenuBarIconFrameLeavesAConsistentVisualMargin() {
        XCTAssertEqual(
            MenuBarIconGeometry.iconFrame,
            CGRect(x: 64, y: 64, width: 896, height: 896)
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
            appIconStyle: .custom,
            customAppIconRelativePath: "CustomAppIcon.png",
            menuBarIconStyle: .lumina,
            customMenuBarIconRelativePath: "CustomMenuBarIcon.png",
            overrideSystemLockShortcut: true,
            lockScreenPlaybackEnabled: true,
            screenSaverPreviousIdleTime: 900
        )

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
    }

    func testLegacySettingsDefaultToLuminaIcon() throws {
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

        let settings = SettingsStore(container: container).load()
        XCTAssertEqual(settings.appIconStyle, .lumina)
        XCTAssertNil(settings.customAppIconRelativePath)
        XCTAssertEqual(settings.menuBarIconStyle, .lumina)
        XCTAssertNil(settings.customMenuBarIconRelativePath)
        XCTAssertFalse(settings.overrideSystemLockShortcut)
        XCTAssertFalse(settings.lockScreenPlaybackEnabled)
        XCTAssertNil(settings.screenSaverPreviousIdleTime)
    }

    func testLegacyPresetIconsMigrateToLuminaIcons() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        let legacyJSON = """
        {
          "appIconStyle": "pink",
          "menuBarIconStyle": "filledPink"
        }
        """
        try Data(legacyJSON.utf8).write(to: container.settingsURL)

        let settings = SettingsStore(container: container).load()
        XCTAssertEqual(settings.appIconStyle, .lumina)
        XCTAssertEqual(settings.menuBarIconStyle, .lumina)
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
        try store.save([content])

        let updated = try store.delete(content, from: [content])

        XCTAssertTrue(updated.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: container.mediaURL(for: content).path)
        )
        try? FileManager.default.removeItem(at: originalURL)
    }

    func testCorruptSettingsFallBackToDefaults() throws {
        let container = try SharedContainer(rootURL: temporaryURL)
        try Data("not json".utf8).write(to: container.settingsURL)
        XCTAssertEqual(SettingsStore(container: container).load(), LuminaSettings())
    }

}
