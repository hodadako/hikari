import AppKit
import AVFoundation
import LuminaCore

@MainActor
final class WallpaperController {
    private let renderer: VideoRenderer
    private var windows: [NSWindow] = []
    private(set) var scalingMode: ScalingMode = .fill

    init(renderer: VideoRenderer) {
        self.renderer = renderer
    }

    func setContentAvailable(_ isAvailable: Bool) {
        if isAvailable {
            if windows.isEmpty {
                rebuildWindows()
            }
        } else {
            closeWindows()
        }
    }

    func rebuildWindowsIfContentAvailable(_ isAvailable: Bool) {
        closeWindows()
        guard isAvailable else { return }
        rebuildWindows()
    }

    private func rebuildWindows() {
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
            )
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle,
                .fullScreenAuxiliary
            ]
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.isOpaque = true
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false

            let playerView = WallpaperPlayerView(
                frame: NSRect(origin: .zero, size: screen.frame.size),
                player: renderer.player
            )
            playerView.scalingMode = scalingMode
            window.contentView = playerView
            window.orderFrontRegardless()
            return window
        }
    }

    func setScalingMode(_ mode: ScalingMode) {
        scalingMode = mode
        for window in windows {
            (window.contentView as? WallpaperPlayerView)?.scalingMode = mode
        }
    }

    func closeWindows() {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
}

private final class WallpaperPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()

    var scalingMode: ScalingMode = .fill {
        didSet {
            playerLayer.videoGravity = scalingMode == .fill
                ? .resizeAspectFill
                : .resizeAspect
        }
    }

    init(frame frameRect: NSRect, player: AVPlayer) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    deinit {
        playerLayer.player = nil
    }
}
