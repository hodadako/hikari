import AppKit
import AVFoundation
import LuminaCore

/// Creates exactly one desktop-level window per connected display. Every
/// window presents the same AVPlayer so multi-display wallpaper playback uses
/// one decoder and one local buffer instead of multiplying both per display.
/// Display IDs come from NSScreenNumber instead of relying on the mutable
/// order of `NSScreen.screens`.
@MainActor
final class WallpaperController {
    private static let wallpaperCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .stationary,
        .ignoresCycle
    ]

    private struct DisplaySession {
        let window: NSWindow
        let view: WallpaperPlayerView
    }

    private var sessions: [UInt32: DisplaySession] = [:]
    private var plans: [WallpaperWindowPlan] = []
    private let renderer = VideoRenderer()
    private var maintenanceTask: Task<Void, Never>?
    private(set) var scalingMode: ScalingMode = .fill
    private var wantsPlayback = false

    var isPlaying: Bool {
        guard wantsPlayback, renderer.currentURL != nil else {
            return false
        }
        return !sessions.isEmpty && renderer.isPlaying
    }

    func setContentAvailable(_ isAvailable: Bool) {
        if isAvailable {
            synchronizeDisplayTopology()
            startMaintenanceMonitoring()
        } else {
            closeWindows()
        }
    }

    func rebuildWindowsIfContentAvailable(_ isAvailable: Bool) {
        guard isAvailable else {
            closeWindows()
            return
        }

        // A wake can leave a desktop-level NSWindow alive while its
        // AVPlayerLayer surface is no longer backed by WindowServer. A
        // topology-only update cannot detect that case when the connected
        // displays have not changed, so recreate every session. This restores
        // the pre-v0.1.15 wake behavior while retaining the current
        // shared-player playback architecture. Preserve the playback position
        // so a surface recovery does not restart the video.
        let playbackPosition = renderer.currentTime
        let shouldPlay = wantsPlayback
        removeAllWindows()
        synchronizeDisplayTopology()

        guard renderer.currentURL != nil else { return }
        renderer.seek(to: playbackPosition)
        if shouldPlay {
            renderer.play()
            startMaintenanceMonitoring()
        } else {
            renderer.pause()
        }
    }

    /// Finalizes a display transition without discarding healthy players.
    ///
    /// Attaching or removing one monitor produces several intermediate
    /// WindowServer snapshots. Those snapshots already create/remove the
    /// affected session in `synchronizeDisplayTopology()`. Recreating every
    /// remaining AVPlayer at the final snapshot makes an otherwise unrelated
    /// display visibly pause, especially when moving between two and three
    /// displays. Reserve a full surface rebuild for wake/Space recovery and
    /// only reload a player here when AVFoundation has reported a real error.
    func finishDisplayTopologyTransitionIfContentAvailable(_ isAvailable: Bool) {
        guard isAvailable else {
            closeWindows()
            return
        }
        synchronizeDisplayTopology()
        recoverFailedPlayer()
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
        guard let url else {
            renderer.stopAndRelease()
            wantsPlayback = false
            return
        }
        renderer.load(url: url, muted: muted)
        recoverFailedPlayer()
        startMaintenanceMonitoring()
    }

    func setMuted(_ muted: Bool) {
        renderer.setMuted(muted)
    }

    func play() {
        wantsPlayback = true
        renderer.play()
        startMaintenanceMonitoring()
    }

    func pause() {
        wantsPlayback = false
        renderer.pause()
        // Keep topology monitoring active while paused. A display attached in
        // this state still needs exactly one prepared wallpaper session, and
        // playback must remain paused when the session is created.
    }

    func setScalingMode(_ mode: ScalingMode) {
        scalingMode = mode
        for session in sessions.values {
            session.view.scalingMode = mode
        }
    }

    func closeWindows() {
        stopMaintenanceMonitoring()
        wantsPlayback = false
        renderer.releaseResources()
        removeAllWindows()
    }

    private func removeAllWindows() {
        for session in sessions.values {
            session.view.detachPlayer()
            session.window.contentView = nil
            session.window.orderOut(nil)
            session.window.close()
        }
        sessions.removeAll()
        plans.removeAll()
    }

    private func createSession(for plan: WallpaperWindowPlan) {
        guard sessions[plan.displayID] == nil else { return }

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
            window: window,
            view: playerView
        )
        window.orderFront(nil)
        playerView.needsLayout = true
        playerView.layoutSubtreeIfNeeded()
    }

    private func removeSession(displayID: UInt32) {
        guard let session = sessions.removeValue(forKey: displayID) else { return }
        session.view.detachPlayer()
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

    private func startMaintenanceMonitoring() {
        guard maintenanceTask == nil else { return }
        let clock = SuspendingClock()
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await clock.sleep(
                    until: clock.now.advanced(by: .seconds(5))
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    // Notifications remain the fast path, while this periodic
                    // reconciliation covers a dropped/coalesced WindowServer
                    // event and a display that materialized late.
                    self?.synchronizeDisplayTopology()
                    self?.recoverFailedPlayer()
                }
            }
        }
    }

    private func stopMaintenanceMonitoring() {
        maintenanceTask?.cancel()
        maintenanceTask = nil
    }

    private func recoverFailedPlayer() {
        guard renderer.hasPlaybackError else { return }
        renderer.reloadCurrentItem()
        if wantsPlayback {
            renderer.play()
        }
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
        detachPlayer()
    }

    func detachPlayer() {
        playerLayer.player = nil
    }
}
