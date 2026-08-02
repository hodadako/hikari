import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        SettingsWindowPresenter.shared.showOnLaunch(model: model)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        SettingsWindowPresenter.shared.show(model: model)
        return true
    }
}
