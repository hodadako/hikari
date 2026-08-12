import AppKit
import SwiftUI

@MainActor
final class SettingsWindowPresenter: NSObject {
    static let shared = SettingsWindowPresenter()

    private var windowController: NSWindowController?
    private var presentedOnLaunch = false
    private var isTerminating = false

    private override init() {
        super.init()
    }

    func showOnLaunch(model: AppModel) {
        guard !presentedOnLaunch else { return }
        presentedOnLaunch = true
        show(model: model)
    }

    func show(model: AppModel) {
        if let window = windowController?.window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView(model: model)
            .frame(minWidth: 560, minHeight: 460)
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: rootView)
        )
        window.title = NSLocalizedString(
            model.contents.isEmpty ? "Set Up Lumina" : "Lumina Settings",
            comment: ""
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 620, height: 520))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.center()

        let controller = NSWindowController(window: window)
        windowController = controller
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
    }

    func prepareForTermination() {
        isTerminating = true
    }

    func hideForAppDeactivation() {
        guard !isTerminating, let window = windowController?.window,
              window.isVisible else {
            return
        }
        window.orderOut(nil)
    }
}

extension SettingsWindowPresenter: NSWindowDelegate {
    /// The close button on a menu-bar app means "hide settings", not "quit
    /// Lumina".  Retaining the controller also makes a subsequent Open
    /// Settings action reliably reuse the same window and its state.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isTerminating else { return true }
        sender.orderOut(nil)
        return false
    }
}
