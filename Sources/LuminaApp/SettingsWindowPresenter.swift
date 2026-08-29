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
            installContentIfNeeded(in: window, model: model)
            configureTitle(of: window, model: model)
            NSApplication.shared.activate(ignoringOtherApps: true)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        installContentIfNeeded(in: window, model: model)
        configureTitle(of: window, model: model)
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

    private func installContentIfNeeded(in window: NSWindow, model: AppModel) {
        guard window.contentViewController == nil else { return }
        let rootView = SettingsView(model: model)
            .frame(minWidth: 560, minHeight: 460)
        window.contentViewController = NSHostingController(rootView: rootView)
    }

    private func configureTitle(of window: NSWindow, model: AppModel) {
        window.title = model.contents.isEmpty
            ? "Set Up \(model.appDisplayName)"
            : "\(model.appDisplayName) Settings"
    }

}

extension SettingsWindowPresenter: NSWindowDelegate {
    /// The close button on a menu-bar app means "hide settings", not "quit
    /// Hikari". Retain the lightweight window shell, but release the hidden
    /// SwiftUI hierarchy so its thumbnails, icon previews, and view graph do
    /// not remain in the agent's steady-state footprint.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isTerminating else { return true }
        sender.orderOut(nil)
        sender.contentViewController = nil
        return false
    }
}
