import Foundation
import UserNotifications

@MainActor
struct UpdateNotificationService {
    static let identifier = "com.hodadako.Hikari.update-available"

    func post(for release: LatestRelease) async -> Bool {
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

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Hikari Update Available", comment: "Update notification title")
        content.body = String(
            format: NSLocalizedString(
                "Version %@ is available. Open Hikari to review the update.",
                comment: "Update notification body"
            ),
            release.displayVersion
        )
        do {
            try await center.add(UNNotificationRequest(
                identifier: Self.identifier, content: content, trigger: nil
            ))
            return true
        } catch {
            return false
        }
    }

    static func opensUpdates(identifier: String, actionIdentifier: String) -> Bool {
        identifier == Self.identifier && actionIdentifier == UNNotificationDefaultActionIdentifier
    }
}
