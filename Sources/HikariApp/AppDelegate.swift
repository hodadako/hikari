import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    private var menuBarStatusItemController: MenuBarStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hikari is normally active while a newly imported video is being
        // prepared. Opt in to foreground presentation so completion still
        // produces the banner the user requested.
        UNUserNotificationCenter.current().delegate = self
        menuBarStatusItemController = MenuBarStatusItemController(model: model)
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
