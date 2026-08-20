import AppKit
import CoreGraphics
import IOKit.ps
import LuminaCore

/// Normalizes noisy WindowServer, power, lock, and screen-saver notifications.
/// State flags are independent pause reasons; no event is allowed to infer an
/// unlock merely because the app became active.
@MainActor
final class SystemStateMonitor {
    var onStateChanged: (() -> Void)?
    var onDisplaysChanged: (() -> Void)?
    var onDisplaysSettled: (() -> Void)?
    var onActiveSpaceChanged: (() -> Void)?
    var onActiveSpaceSettled: (() -> Void)?

    private(set) var isSleeping = false
    private(set) var isScreenLocked = false
    private(set) var isScreenSaverRunning = false
    private(set) var isOnBattery = false

    private var notificationTokens: [NSObjectProtocol] = []
    private var stateTask: Task<Void, Never>?
    private var displayTask: Task<Void, Never>?
    private var spaceTask: Task<Void, Never>?

    // WindowServer can publish the screen-parameter notification before the
    // newly attached display has a stable NSScreen/window surface. Recheck
    // the topology at increasing delays, but only recreate AVPlayer-backed
    // surfaces after the final snapshot has settled.
    private let displayRecoveryIntervals: [UInt64] = [
        0,
        250_000_000,
        650_000_000
    ]

    // WindowServer finishes a Spaces mutation asynchronously. A single
    // callback can run while the new desktop is still being materialized, so
    // use a short recovery sequence and collapse overlapping notifications.
    // The final pass is deliberately distinct: it is safe to recreate an
    // AVPlayerLayer-backed desktop surface only after the Space settles.
    private let spaceRecoveryDelays: [UInt64] = [
        80_000_000,
        220_000_000,
        400_000_000
    ]

    func start() {
        guard notificationTokens.isEmpty else { return }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, name: NSWorkspace.willSleepNotification) { [weak self] in
            guard let self else { return }
            isSleeping = true
            scheduleStateChanged()
        }
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification) { [weak self] in
            guard let self else { return }
            isSleeping = false
            refreshPowerState()
            refreshLockState()
            refreshScreenSaverState()
            // WindowServer may still be rebuilding display surfaces at wake.
            scheduleRecovery(after: 350_000_000)
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidSleepNotification) { [weak self] in
            guard let self else { return }
            isSleeping = true
            scheduleStateChanged()
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidWakeNotification) { [weak self] in
            guard let self else { return }
            isSleeping = false
            refreshPowerState()
            refreshLockState()
            refreshScreenSaverState()
            scheduleRecovery(after: 250_000_000)
        }
        observe(workspaceCenter, name: NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.scheduleActiveSpaceChanged()
        }

        let defaultCenter = NotificationCenter.default
        observe(defaultCenter, name: NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.scheduleDisplaysChanged()
        }
        observe(defaultCenter, name: NSApplication.didBecomeActiveNotification) { [weak self] in
            guard let self else { return }
            // Becoming active is not proof of an unlock. Ask WindowServer for
            // the current lock state and let the normal policy decide.  An
            // ordinary app activation does not invalidate display surfaces;
            // rebuilding them here visibly flashes the desktop black before
            // AVFoundation has produced a new frame.
            refreshPowerState()
            refreshLockState()
            refreshScreenSaverState()
            scheduleStateChanged(after: 180_000_000)
        }
        observe(defaultCenter, name: .NSProcessInfoPowerStateDidChange) { [weak self] in
            guard let self else { return }
            refreshPowerState()
            scheduleStateChanged()
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, name: Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            guard let self else { return }
            isScreenLocked = true
            scheduleStateChanged()
        }
        observe(distributed, name: Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            guard let self else { return }
            isScreenLocked = false
            // ScreenSaverEngine can exit before its bundle has an opportunity
            // to publish the stop signal.  Do not leave the wallpaper paused
            // behind a stale screen-saver reason after a successful unlock.
            isScreenSaverRunning = false
            scheduleStateChanged()
            // WindowServer tears down the lock-screen surfaces asynchronously.
            // Re-evaluate playback after that transition, but do not treat an
            // unlock as a display change. Rebuilding the desktop AVPlayerLayer
            // here closes the live surface and produces a black flash.
            scheduleStateChanged(after: 450_000_000)
        }
        observe(distributed, name: InterprocessSignal.screenSaverDidStart) { [weak self] in
            guard let self else { return }
            isScreenSaverRunning = true
            scheduleStateChanged()
        }
        observe(distributed, name: InterprocessSignal.screenSaverDidStop) { [weak self] in
            guard let self else { return }
            isScreenSaverRunning = false
            scheduleStateChanged()
        }

        refreshPowerState()
        refreshLockState()
    }

    func stop() {
        stateTask?.cancel()
        displayTask?.cancel()
        spaceTask?.cancel()
        stateTask = nil
        displayTask = nil
        spaceTask = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    private func refreshPowerState() {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else {
            isOnBattery = false
            return
        }
        isOnBattery = (source as String) == kIOPSBatteryPowerValue
    }

    private func refreshLockState() {
        // This value is authoritative when available and does not assume that
        // app activation implies unlock. The distributed notifications remain
        // the fallback on systems where the session dictionary is unavailable.
        guard let values = CGSessionCopyCurrentDictionary() as? [String: Any],
              let value = values["CGSSessionScreenIsLocked"] else {
            return
        }
        if let locked = value as? Bool {
            isScreenLocked = locked
        } else if let locked = value as? NSNumber {
            isScreenLocked = locked.boolValue
        }
    }

    private func refreshScreenSaverState() {
        // A lost stop notification must not leave playback paused forever. Do
        // not infer a start here; the screen saver bundle posts the positive
        // transition, while this check only clears stale state.
        let screenSaverIsRunning = NSWorkspace.shared.runningApplications.contains {
            let name = $0.executableURL?.lastPathComponent
                ?? $0.localizedName
                ?? ""
            return name == "ScreenSaverEngine" || name == "legacyScreenSaver"
        }
        if !screenSaverIsRunning {
            isScreenSaverRunning = false
        }
    }

    private func observe(
        _ center: NotificationCenter,
        name: Notification.Name,
        action: @escaping @MainActor () -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            Task { @MainActor in action() }
        }
        notificationTokens.append(token)
    }

    private func scheduleStateChanged(after delay: UInt64 = 120_000_000) {
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.onStateChanged?()
            }
        }
    }

    private func scheduleDisplaysChanged(after delay: UInt64 = 120_000_000) {
        displayTask?.cancel()
        let recoveryIntervals = displayRecoveryIntervals
        let recoveryPasses = DisplayRecoveryPolicy.passes(for: recoveryIntervals)
        displayTask = Task { [weak self] in
            for (index, interval) in recoveryIntervals.enumerated() {
                try? await Task.sleep(
                    nanoseconds: delay + interval
                )
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self else { return }
                    switch recoveryPasses[index] {
                    case .topology:
                        self.onDisplaysChanged?()
                    case .settled:
                        self.onDisplaysSettled?()
                    }
                }
            }
        }
    }

    private func scheduleActiveSpaceChanged(after delay: UInt64 = 80_000_000) {
        let recoveryDelays = [delay] + Array(spaceRecoveryDelays.dropFirst())
        spaceTask?.cancel()
        spaceTask = Task { [weak self] in
            for (index, recoveryDelay) in recoveryDelays.enumerated() {
                try? await Task.sleep(nanoseconds: recoveryDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    if index == recoveryDelays.indices.last {
                        self?.onActiveSpaceSettled?()
                    } else {
                        self?.onActiveSpaceChanged?()
                    }
                }
            }
        }
    }

    private func scheduleRecovery(after delay: UInt64) {
        scheduleDisplaysChanged(after: delay)
        scheduleStateChanged(after: delay)
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }
}
