import AppKit
import AVFoundation
import LuminaCore

/// Creates exactly one desktop-level window and one AVPlayer session per
/// connected display. Display IDs come from NSScreenNumber instead of relying
/// on the mutable order of `NSScreen.screens`.
@MainActor
final class WallpaperController {
    private static let wallpaperCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .stationary,
        .ignoresCycle
    ]

    private struct DisplaySession {
        let renderer: VideoRenderer
        let window: NSWindow
        let view: WallpaperPlayerView
    }

    private var sessions: [UInt32: DisplaySession] = [:]
    private var plans: [WallpaperWindowPlan] = []
    private let playback = PlaybackCoordinator()
    private var driftTask: Task<Void, Never>?
    private(set) var scalingMode: ScalingMode = .fill

    var isPlaying: Bool {
        guard playback.wantsPlayback, playback.currentURL != nil else {
            return false
        }
        return !sessions.isEmpty && sessions.values.allSatisfy { $0.renderer.isPlaying }
    }

    func setContentAvailable(_ isAvailable: Bool) {
        if isAvailable {
            synchronizeDisplayTopology()
        } else {
            closeWindows()
        }
    }

    func rebuildWindowsIfContentAvailable(_ isAvailable: Bool) {
        setContentAvailable(isAvailable)
    }

    func refreshWindowsForActiveSpaceIfContentAvailable(_ isAvailable: Bool) {
        guard isAvailable else {
            closeWindows()
            return
        }
        synchronizeDisplayTopology()
        for session in sessions.values {
            // Reassert the all-Spaces membership after Mission Control creates
            // or removes a desktop. WindowServer may otherwise retain the
            // previous Space assignment until the next transition.
            session.window.collectionBehavior = Self.wallpaperCollectionBehavior
            // Desktop-level windows are non-key and cannot cover app content.
            // Normal ordering is sufficient; forced ordering could promote a
            // stale wallpaper surface over other WindowServer surfaces.
            session.window.orderFront(nil)
        }
    }

    @discardableResult
    func synchronizeDisplayTopology() -> DisplayTopologyDiff {
        let descriptors = currentDisplayDescriptors()
        let newPlans = DisplayTopology.plans(for: descriptors)
        let diff = DisplayTopology.diff(from: plans, to: newPlans)

        for displayID in diff.removed {
            removeSession(displayID: displayID)
        }
        for plan in diff.updated {
            guard let session = sessions[plan.displayID] else { continue }
            session.window.setFrame(plan.frame, display: true, animate: false)
            session.window.collectionBehavior = Self.wallpaperCollectionBehavior
            session.view.backingScaleFactor = plan.backingScaleFactor
            session.view.frame = session.window.contentView?.bounds ?? .zero
            session.view.needsLayout = true
            session.view.layoutSubtreeIfNeeded()
            session.window.orderFront(nil)
        }

        // Recover from a topology snapshot that previously contained a
        // display but failed to create its session while WindowServer was
        // still materializing it.
        for plan in newPlans where sessions[plan.displayID] == nil {
            createSession(for: plan)
        }

        plans = newPlans
        return diff
    }

    func setContent(url: URL?, muted: Bool) {
        playback.setContent(url: url, muted: muted)
        playback.recoverFailedSessions()
        if playback.wantsPlayback {
            startDriftMonitoring()
        }
    }

    func setMuted(_ muted: Bool) {
        playback.setMuted(muted)
    }

    func play() {
        playback.play()
        startDriftMonitoring()
    }

    func pause() {
        playback.pause()
        stopDriftMonitoring()
    }

    func setScalingMode(_ mode: ScalingMode) {
        scalingMode = mode
        for session in sessions.values {
            session.view.scalingMode = mode
        }
    }

    func closeWindows() {
        stopDriftMonitoring()
        playback.releaseAll()
        for session in sessions.values {
            session.window.contentView = nil
            session.window.orderOut(nil)
            session.window.close()
        }
        sessions.removeAll()
        plans.removeAll()
    }

    private func createSession(for plan: WallpaperWindowPlan) {
        guard sessions[plan.displayID] == nil else { return }

        let renderer = VideoRenderer()
        let window = NSWindow(
            contentRect: plan.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // A desktop window is below the menu bar, Dock, desktop icons, and
        // normal app windows. It also avoids the menu-bar artifact caused by
        // promoting a wallpaper window unconditionally.
        window.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow))
        )
        window.collectionBehavior = Self.wallpaperCollectionBehavior
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.isMovable = false

        let playerView = WallpaperPlayerView(
            frame: NSRect(origin: .zero, size: plan.frame.size),
            player: renderer.player,
            backingScaleFactor: plan.backingScaleFactor
        )
        playerView.autoresizingMask = [.width, .height]
        playerView.scalingMode = scalingMode
        window.contentView = playerView

        sessions[plan.displayID] = DisplaySession(
            renderer: renderer,
            window: window,
            view: playerView
        )
        playback.addSession(id: plan.displayID, session: renderer)
        window.orderFront(nil)
        playerView.needsLayout = true
        playerView.layoutSubtreeIfNeeded()
    }

    private func removeSession(displayID: UInt32) {
        guard let session = sessions.removeValue(forKey: displayID) else { return }
        playback.removeSession(id: displayID)
        session.window.contentView = nil
        session.window.orderOut(nil)
        session.window.close()
    }

    private func currentDisplayDescriptors() -> [DisplayDescriptor] {
        NSScreen.screens.enumerated().map { index, screen in
            DisplayDescriptor(
                id: stableDisplayID(for: screen, fallbackIndex: index),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScaleFactor: screen.backingScaleFactor,
                isMain: screen == NSScreen.main
            )
        }
    }

    private func stableDisplayID(for screen: NSScreen, fallbackIndex: Int) -> UInt32 {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.uint32Value
        }

        // NSScreenNumber is present for real macOS displays. Keep a
        // deterministic fallback for unusual test/headless screens.
        var hasher = Hasher()
        hasher.combine(screen.frame.origin.x)
        hasher.combine(screen.frame.origin.y)
        hasher.combine(screen.frame.size.width)
        hasher.combine(screen.frame.size.height)
        hasher.combine(screen.localizedName)
        hasher.combine(fallbackIndex)
        return UInt32(truncatingIfNeeded: hasher.finalize())
    }

    private func startDriftMonitoring() {
        guard driftTask == nil else { return }
        driftTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.playback.recoverFailedSessions()
                    self?.playback.synchronizeDrift()
                }
            }
        }
    }

    private func stopDriftMonitoring() {
        driftTask?.cancel()
        driftTask = nil
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

    var backingScaleFactor: Double {
        didSet {
            let scale = CGFloat(backingScaleFactor)
            layer?.contentsScale = scale
            playerLayer.contentsScale = scale
        }
    }

    init(frame frameRect: NSRect, player: AVPlayer, backingScaleFactor: Double) {
        self.backingScaleFactor = backingScaleFactor
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsScale = CGFloat(backingScaleFactor)
        playerLayer.player = player
        playerLayer.contentsScale = CGFloat(backingScaleFactor)
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
