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
    private var iconHostingView: PassthroughHostingView<MenuBarSparkleView>?
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

        let hostingView = PassthroughHostingView(
            rootView: MenuBarSparkleView(model: model)
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

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private struct MenuBarSparkleView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.shouldPulseMenuBarSparkle {
                sparkle
            } else {
                Color.clear
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
                .font(.system(size: 7, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.white)
                .symbolEffect(
                    .pulse.wholeSymbol,
                    options: .repeating,
                    isActive: !reduceMotion
                )
        } else if let heartbeatImage = model.menuBarHeartbeatImage {
            LegacyHeartbeatView(
                image: heartbeatImage,
                reduceMotion: reduceMotion
            )
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
