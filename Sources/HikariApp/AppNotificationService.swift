import Foundation
import HikariCore
import UserNotifications

@MainActor
struct AppNotificationService {
    static let updateIdentifier = "com.hodadako.Hikari.update-available"
    private static let nativeLockPreparingPrefix =
        "com.hodadako.Hikari.native-lock-preparing."
    private static let nativeLockReadyPrefix =
        "com.hodadako.Hikari.native-lock-ready."

    func postUpdateAvailable(for release: LatestRelease) async -> Bool {
        await post(Self.updateAvailableRequest(for: release))
    }

    func postNativeLockPreparationStarted(for content: LiveContent) async -> Bool {
        await post(Self.nativeLockPreparationStartedRequest(for: content))
    }

    func postNativeLockPreparationReady(for content: LiveContent) async -> Bool {
        await post(Self.nativeLockPreparationReadyRequest(for: content))
    }

    static func updateAvailableRequest(for release: LatestRelease) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString(
            "Hikari Update Available",
            comment: "Update notification title"
        )
        content.body = String(
            format: NSLocalizedString(
                "Version %@ is available. Open Hikari to review the update.",
                comment: "Update notification body"
            ),
            release.displayVersion
        )
        return UNNotificationRequest(
            identifier: updateIdentifier,
            content: content,
            trigger: nil
        )
    }

    static func nativeLockPreparationStartedRequest(
        for content: LiveContent
    ) -> UNNotificationRequest {
        let notification = UNMutableNotificationContent()
        notification.title = NSLocalizedString(
            "Preparing Lock Screen Video",
            comment: "Native Lock preparation start notification title"
        )
        notification.body = String(
            format: NSLocalizedString(
                "%@ is being prepared for the Lock Screen.",
                comment: "Native Lock preparation start notification body"
            ),
            content.title
        )
        notification.sound = .default
        notification.threadIdentifier = "com.hodadako.Hikari.native-lock.\(content.id.uuidString)"
        return UNNotificationRequest(
            identifier: nativeLockPreparingPrefix + content.id.uuidString,
            content: notification,
            trigger: nil
        )
    }

    static func nativeLockPreparationReadyRequest(
        for content: LiveContent
    ) -> UNNotificationRequest {
        let notification = UNMutableNotificationContent()
        notification.title = NSLocalizedString(
            "Lock Screen Video Ready",
            comment: "Native Lock preparation completion notification title"
        )
        notification.body = String(
            format: NSLocalizedString(
                "%@ is ready to apply to the Lock Screen.",
                comment: "Native Lock preparation completion notification body"
            ),
            content.title
        )
        notification.sound = .default
        notification.threadIdentifier = "com.hodadako.Hikari.native-lock.\(content.id.uuidString)"
        return UNNotificationRequest(
            identifier: nativeLockReadyPrefix + content.id.uuidString,
            content: notification,
            trigger: nil
        )
    }

    static func opensUpdates(identifier: String, actionIdentifier: String) -> Bool {
        identifier == updateIdentifier
            && actionIdentifier == UNNotificationDefaultActionIdentifier
    }

    static func opensNativeLockSettings(
        identifier: String,
        actionIdentifier: String
    ) -> Bool {
        actionIdentifier == UNNotificationDefaultActionIdentifier
            && (identifier.hasPrefix(nativeLockPreparingPrefix)
                || identifier.hasPrefix(nativeLockReadyPrefix))
    }

    private func post(_ request: UNNotificationRequest) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                return false
            }
        case .authorized, .provisional:
            break
        default:
            return false
        }

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }
}
