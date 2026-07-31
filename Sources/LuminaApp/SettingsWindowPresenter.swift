import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?
    private var presentedInitialSetup = false

    private init() {}

    func showInitialSetupIfNeeded(model: AppModel) {
        guard !presentedInitialSetup, model.contents.isEmpty else { return }
        presentedInitialSetup = true
        show(model: model)
    }

    func show(model: AppModel) {
        if let window = windowController?.window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView(model: model)
            .frame(minWidth: 560, minHeight: 460)
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: rootView)
        )
        window.title = model.contents.isEmpty ? "Set Up Lumina" : "Lumina Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.isReleasedWhenClosed = false
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }
}
