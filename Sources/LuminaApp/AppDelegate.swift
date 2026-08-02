import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
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
}
