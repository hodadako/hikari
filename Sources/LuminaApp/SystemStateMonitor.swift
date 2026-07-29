import AppKit
import IOKit.ps
import LuminaCore

@MainActor
final class SystemStateMonitor {
    var onStateChanged: (() -> Void)?
    var onDisplaysChanged: (() -> Void)?

    private(set) var isSleeping = false
    private(set) var isScreenLocked = false
    private(set) var isScreenSaverRunning = false
    private(set) var isOnBattery = false

    private var notificationTokens: [NSObjectProtocol] = []

    func start() {
        guard notificationTokens.isEmpty else { return }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, name: NSWorkspace.willSleepNotification) { [weak self] in
            self?.isSleeping = true
            self?.notifyStateChanged()
        }
        observe(workspaceCenter, name: NSWorkspace.didWakeNotification) { [weak self] in
            self?.isSleeping = false
            self?.isScreenSaverRunning = false
            self?.refreshPowerState()
            self?.notifyStateChanged()
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidSleepNotification) { [weak self] in
            self?.isSleeping = true
            self?.notifyStateChanged()
        }
        observe(workspaceCenter, name: NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.isSleeping = false
            self?.isScreenSaverRunning = false
            self?.notifyStateChanged()
        }

        let defaultCenter = NotificationCenter.default
        observe(defaultCenter, name: NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.onDisplaysChanged?()
            self?.notifyStateChanged()
        }
        observe(defaultCenter, name: NSApplication.didBecomeActiveNotification) { [weak self] in
            self?.isScreenSaverRunning = false
            self?.isScreenLocked = false
            self?.refreshPowerState()
            self?.notifyStateChanged()
        }
        observe(defaultCenter, name: .NSProcessInfoPowerStateDidChange) { [weak self] in
            self?.refreshPowerState()
            self?.notifyStateChanged()
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, name: Notification.Name("com.apple.screenIsLocked")) { [weak self] in
            self?.isScreenLocked = true
            self?.notifyStateChanged()
        }
        observe(distributed, name: Notification.Name("com.apple.screenIsUnlocked")) { [weak self] in
            self?.isScreenLocked = false
            self?.isScreenSaverRunning = false
            self?.notifyStateChanged()
        }
        observe(distributed, name: InterprocessSignal.screenSaverDidStart) { [weak self] in
            self?.isScreenSaverRunning = true
            self?.notifyStateChanged()
        }
        observe(distributed, name: InterprocessSignal.screenSaverDidStop) { [weak self] in
            self?.isScreenSaverRunning = false
            self?.notifyStateChanged()
        }
        refreshPowerState()
    }

    func stop() {
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

    private func notifyStateChanged() {
        onStateChanged?()
    }

    deinit {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            DistributedNotificationCenter.default().removeObserver(token)
        }
    }
}
