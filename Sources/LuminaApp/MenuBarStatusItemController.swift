import AppKit
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
    private var iconHostingView: PassthroughHostingView<MenuBarCompositeIconView>?
    private var externalClickMonitor: Any?

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
    }

    deinit {
        if let externalClickMonitor {
            NSEvent.removeMonitor(externalClickMonitor)
        }
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = nil
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = model.appDisplayName
        button.setAccessibilityLabel(model.appDisplayName)

        let hostingView = PassthroughHostingView(
            rootView: MenuBarCompositeIconView(model: model)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            hostingView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            hostingView.widthAnchor.constraint(equalToConstant: 18),
            hostingView.heightAnchor.constraint(equalToConstant: 18)
        ])
        iconHostingView = hostingView
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 300, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(model: model)
        )
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

    /// `NSPopover.behavior.transient` normally dismisses a status-item popover
    /// after a click elsewhere. In an agent app, AppKit can leave that popover
    /// open when the click belongs to another application or the desktop.
    /// Monitor those external mouse-down events while shown as a fallback.
    private func installExternalClickMonitor() {
        guard externalClickMonitor == nil else { return }
        externalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }
    }

    private func removeExternalClickMonitor() {
        guard let externalClickMonitor else { return }
        NSEvent.removeMonitor(externalClickMonitor)
        self.externalClickMonitor = nil
    }
}

extension MenuBarStatusItemController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        installExternalClickMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeExternalClickMonitor()
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct MenuBarCompositeIconView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(nsImage: model.menuBarIconImage)
                .resizable()
                .interpolation(.high)
                .renderingMode(model.menuBarIconIsTemplate ? .template : .original)
                .foregroundStyle(.primary)
                .scaledToFit()

            if model.shouldPulseMenuBarSparkle {
                sparkle
                    .zIndex(1)
            }
        }
        .frame(width: 18, height: 18)
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var sparkle: some View {
        if #available(macOS 14.0, *) {
            Image(systemName: "sparkle")
                .font(.system(size: 5.5, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .symbolEffect(
                    .pulse.wholeSymbol,
                    options: .repeating,
                    isActive: !reduceMotion
                )
                .offset(y: -2)
        } else if let heartbeatImage = model.menuBarHeartbeatImage {
            LegacyHeartbeatView(
                image: heartbeatImage,
                reduceMotion: reduceMotion
            )
            .frame(width: 5.5, height: 5.5)
            .offset(y: -2)
        }
    }
}

private struct LegacyHeartbeatView: View {
    let image: NSImage
    let reduceMotion: Bool
    @State private var isPulsing = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .opacity(isPulsing ? 0.3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: 0.85)
                        .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}
