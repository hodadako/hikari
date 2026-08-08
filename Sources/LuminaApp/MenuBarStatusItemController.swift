import AppKit
import Combine
import SwiftUI

/// Owns Lumina's status item independently from SwiftUI's MenuBarExtra scene.
///
/// MenuBarExtra can drop a custom NSImage label while the application itself
/// continues running. An explicit NSStatusItem keeps the icon and popover
/// lifecycle observable and lets custom menu-bar artwork remain supported.
@MainActor
final class MenuBarStatusItemController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var modelObservation: AnyCancellable?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()

        modelObservation = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
            }
    }

    deinit {
        modelObservation?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "Lumina"
        button.setAccessibilityLabel("Lumina")
        updateIcon()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(model: model)
        )
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let image = model.menuBarIconImage
        image.isTemplate = model.menuBarIconIsTemplate
        button.image = image
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
        }
    }
}
