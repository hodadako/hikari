import HikariCore
import UserNotifications
import XCTest

@MainActor
final class AppNotificationServiceTests: XCTestCase {
    func testNativeLockPreparationNotifiesAtStartAndWhenReady() {
        let content = LiveContent(
            title: "Ocean",
            relativePath: "Media/ocean.mov",
            fileSize: 1,
            duration: 10,
            width: 1920,
            height: 1080,
            codec: "HEVC",
            thumbnailRelativePath: nil
        )

        let preparing = AppNotificationService.nativeLockPreparationStartedRequest(
            for: content
        )
        let ready = AppNotificationService.nativeLockPreparationReadyRequest(
            for: content
        )

        XCTAssertNotEqual(preparing.identifier, ready.identifier)
        XCTAssertEqual(preparing.content.threadIdentifier, ready.content.threadIdentifier)
        XCTAssertNil(preparing.trigger)
        XCTAssertNil(ready.trigger)
        XCTAssertEqual(
            preparing.content.title,
            NSLocalizedString(
                "Preparing Lock Screen Video",
                comment: "Native Lock preparation start notification title"
            )
        )
        XCTAssertEqual(
            preparing.content.body,
            String(
                format: NSLocalizedString(
                    "%@ is being prepared for the Lock Screen.",
                    comment: "Native Lock preparation start notification body"
                ),
                content.title
            )
        )
        XCTAssertEqual(
            ready.content.title,
            NSLocalizedString(
                "Lock Screen Video Ready",
                comment: "Native Lock preparation completion notification title"
            )
        )
        XCTAssertEqual(
            ready.content.body,
            String(
                format: NSLocalizedString(
                    "%@ is ready to apply to the Lock Screen.",
                    comment: "Native Lock preparation completion notification body"
                ),
                content.title
            )
        )
        XCTAssertTrue(AppNotificationService.opensNativeLockSettings(
            identifier: preparing.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        XCTAssertTrue(AppNotificationService.opensNativeLockSettings(
            identifier: ready.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        XCTAssertFalse(AppNotificationService.opensNativeLockSettings(
            identifier: ready.identifier,
            actionIdentifier: UNNotificationDismissActionIdentifier
        ))
    }

    func testUpdateAvailableNotificationKeepsVersionAndAboutAction() {
        let release = LatestRelease(
            tagName: "v0.4.0",
            name: "Hikari v0.4.0",
            htmlURL: URL(string: "https://github.com/hodadako/hikari/releases/tag/v0.4.0")!,
            assets: []
        )
        let request = AppNotificationService.updateAvailableRequest(for: release)

        XCTAssertEqual(
            request.identifier,
            AppNotificationService.updateIdentifier
        )
        XCTAssertTrue(request.content.body.contains(release.displayVersion))
        XCTAssertTrue(AppNotificationService.opensUpdates(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        XCTAssertFalse(AppNotificationService.opensNativeLockSettings(
            identifier: request.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
    }
}
