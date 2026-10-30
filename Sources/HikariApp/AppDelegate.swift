import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    private var menuBarStatusItemController: MenuBarStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hikari stays active while a Lock Screen video is prepared. Opt in
        // to foreground presentation so progress and completion remain visible.
        UNUserNotificationCenter.current().delegate = self
        menuBarStatusItemController = MenuBarStatusItemController(model: model)
        model.startUpdateMonitoring()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SettingsWindowPresenter.shared.showOnLaunch(model: self.model)
            // Queue playback separately so AppKit can present the settings
            // window before AVFoundation and WindowServer begin creating the
            // desktop wallpaper surfaces.
            DispatchQueue.main.async { [weak self] in
                self?.model.startInitialPlayback()
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        SettingsWindowPresenter.shared.show(model: model)
        return true
    }

    /// Hikari is an agent app: closing its only settings window must leave the
    /// status item and live wallpaper process running.  This also protects the
    /// app from AppKit's normal "last window closed" termination path.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        SettingsWindowPresenter.shared.prepareForTermination()
        return .terminateNow
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let actionIdentifier = response.actionIdentifier
        Task { @MainActor [weak self] in
            if AppNotificationService.opensUpdates(
                identifier: identifier, actionIdentifier: actionIdentifier
            ) {
                self?.menuBarStatusItemController?.showUpdates()
            } else if AppNotificationService.opensNativeLockSettings(
                identifier: identifier, actionIdentifier: actionIdentifier
            ) {
                guard let self else {
                    completionHandler()
                    return
                }
                SettingsWindowPresenter.shared.show(
                    model: self.model,
                    section: .general
                )
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (
            UNNotificationPresentationOptions
        ) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
