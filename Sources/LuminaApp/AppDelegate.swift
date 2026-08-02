import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor weak var model: AppModel?

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        Task { @MainActor [weak self] in
            guard let model = self?.model else { return }
            SettingsWindowPresenter.shared.show(model: model)
        }
        return true
    }
}
