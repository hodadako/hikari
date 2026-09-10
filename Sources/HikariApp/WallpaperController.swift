import AppKit
import AVFoundation
import HikariCore

/// Maintains one desktop-level window per connected display, with a temporary
/// replacement behind it during surface recovery. Every window presents the
/// same AVPlayer so multi-display wallpaper playback uses
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
    private var replacementSessions: [UInt32: DisplaySession] = [:]
    private var surfaceRecoveryTask: Task<Void, Never>?
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

        // Mission Control can invalidate a window's presentation surface even
        // though its player is healthy. Prepare replacements behind the live
        // windows, then hand off each display only when it has a video frame.
        // Closing all windows first exposes black while AVFoundation prepares
        // the new layers. Seeking the shared player also flushes healthy layers
        // and is unnecessary: replacement layers use the same running clock.
        synchronizeDisplayTopology()
        guard renderer.currentURL != nil else { return }

        for plan in plans where replacementSessions[plan.displayID] == nil {
            guard let current = sessions[plan.displayID] else { continue }
            let replacement = makeSession(for: plan)
            replacementSessions[plan.displayID] = replacement
            replacement.window.order(.below, relativeTo: current.window.windowNumber)
        }
        startSurfaceRecovery()
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
            discardReplacement(displayID: plan.displayID)
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
        if renderer.currentURL != url {
            cancelSurfaceRecovery()
        }
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
        for session in replacementSessions.values {
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
        cancelSurfaceRecovery()
        for session in sessions.values {
            close(session)
        }
        sessions.removeAll()
        plans.removeAll()
    }

    private func createSession(for plan: WallpaperWindowPlan) {
        guard sessions[plan.displayID] == nil else { return }
        let session = makeSession(for: plan)
        sessions[plan.displayID] = session
        session.window.orderFront(nil)
    }

    private func makeSession(for plan: WallpaperWindowPlan) -> DisplaySession {
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

        playerView.needsLayout = true
        playerView.layoutSubtreeIfNeeded()
        return DisplaySession(window: window, view: playerView)
    }

    private func removeSession(displayID: UInt32) {
        discardReplacement(displayID: displayID)
        guard let session = sessions.removeValue(forKey: displayID) else { return }
        close(session)
    }

    private func close(_ session: DisplaySession) {
        session.view.detachPlayer()
        session.window.contentView = nil
        session.window.orderOut(nil)
        session.window.close()
    }

    private func discardReplacement(displayID: UInt32) {
        guard let session = replacementSessions.removeValue(forKey: displayID) else { return }
        close(session)
    }

    private func cancelSurfaceRecovery() {
        surfaceRecoveryTask?.cancel()
        surfaceRecoveryTask = nil
        for displayID in Array(replacementSessions.keys) {
            discardReplacement(displayID: displayID)
        }
    }

    private func startSurfaceRecovery() {
        guard surfaceRecoveryTask == nil, !replacementSessions.isEmpty else { return }
        surfaceRecoveryTask = Task { @MainActor [weak self] in
            // Readiness, not this deadline, permits the handoff. A stalled or
            // non-video item must never replace a visible window with black,
            // nor retain a second set of surfaces indefinitely.
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(3))
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled, let self else { return }
                for displayID in Array(self.replacementSessions.keys) {
                    guard let replacement = self.replacementSessions[displayID],
                          replacement.view.isReadyForDisplay,
                          let current = self.sessions[displayID] else { continue }
                    replacement.window.order(.above, relativeTo: current.window.windowNumber)
                    self.sessions[displayID] = replacement
                    self.replacementSessions.removeValue(forKey: displayID)
                    self.close(current)
                }
                if self.replacementSessions.isEmpty || clock.now >= deadline {
                    self.cancelSurfaceRecovery()
                    return
                }
            }
        }
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

    var isReadyForDisplay: Bool { playerLayer.isReadyForDisplay }

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
