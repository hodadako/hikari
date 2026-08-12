import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()
    private var menuBarStatusItemController: MenuBarStatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarStatusItemController = MenuBarStatusItemController(model: model)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            SettingsWindowPresenter.shared.showOnLaunch(model: self.model)
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        SettingsWindowPresenter.shared.show(model: model)
        return true
    }

    /// Settings belongs to a menu-bar utility, so it should not remain over
    /// another app or the desktop after Lumina loses focus. This deliberately
    /// observes application deactivation (rather than key-window changes),
    /// allowing Lumina-owned sheets such as the import panel to work normally.
    func applicationDidResignActive(_ notification: Notification) {
        SettingsWindowPresenter.shared.hideForAppDeactivation()
    }

    /// Lumina is an agent app: closing its only settings window must leave the
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
