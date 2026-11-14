import AppKit
import XCTest
import HikariCore

@MainActor
final class SystemStateMonitorTests: XCTestCase {
    func testRapidRelockCancelsOldRefreshBeforeDebouncedStateCallback() async throws {
        // Use a private center: never send real system lock notifications.
        let center = NotificationCenter()
        let monitor = SystemStateMonitor(
            sessionLockState: { nil }, lockNotificationCenter: center
        )
        var schedule = NativeLockMaintenanceSchedule()
        var uptime = 10.0
        var lockEvents = 0
        var unlockEvents = 0
        monitor.onScreenLocked = {
            lockEvents += 1
            schedule.cancel()
        }
        monitor.onScreenUnlocked = {
            unlockEvents += 1
            schedule.didUnlock(at: uptime)
        }
        monitor.start()
        defer { monitor.stop() }
        center.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(schedule.refreshRequested)
        center.post(name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(lockEvents, 1)
        XCTAssertFalse(schedule.refreshRequested)
        XCTAssertFalse(monitor.permitsNativeMaintenance)
        uptime = 20
        center.post(name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(unlockEvents, 2)
        XCTAssertFalse(schedule.permitsMaintenance(at: 20.65))
        XCTAssertTrue(schedule.permitsMaintenance(at: 22))
    }

    func testFreshSessionLockBlocksMaintenanceBeforeNotificationDelivery() {
        var locked: Bool? = false
        let monitor = SystemStateMonitor(sessionLockState: { locked })
        XCTAssertTrue(monitor.permitsNativeMaintenance)
        locked = true
        XCTAssertFalse(monitor.isScreenLocked) // No notification delivered yet.
        XCTAssertFalse(monitor.permitsNativeMaintenance)
        locked = false
        XCTAssertTrue(monitor.permitsNativeMaintenance)
    }

    func testMissingSessionSnapshotPreservesKnownLockedState() {
        var locked: Bool? = true
        let monitor = SystemStateMonitor(sessionLockState: { locked })
        monitor.start()
        defer { monitor.stop() }
        XCTAssertTrue(monitor.isScreenLocked)
        locked = nil
        XCTAssertFalse(monitor.permitsNativeMaintenance)
    }

    func testSleepBlocksMaintenanceWithUnlockedSnapshot() async throws {
        let monitor = SystemStateMonitor(sessionLockState: { false })
        monitor.start()
        defer { monitor.stop() }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(monitor.permitsNativeMaintenance)
    }

    func testWakeSurfaceRecoverySurvivesDisplayTaskReplacement() async throws {
        let monitor = SystemStateMonitor()
        let recovered = expectation(description: "Wake surfaces recovered after topology settled")
        recovered.assertForOverFulfill = true
        var topologySettled = false
        monitor.onDisplaysSettled = { topologySettled = true }
        monitor.onWakeSettled = {
            XCTAssertTrue(topologySettled)
            recovered.fulfill()
        }
        monitor.start()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(150))
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await fulfillment(of: [recovered], timeout: 4)
        try await Task.sleep(for: .milliseconds(500))
    }

    func testDisplayChangeAloneDoesNotRequestWakeSurfaceRecovery() async {
        let monitor = SystemStateMonitor()
        let settled = expectation(description: "Display topology settled")
        let noWake = expectation(description: "No wake surface rebuild")
        noWake.isInverted = true
        monitor.onDisplaysSettled = { settled.fulfill() }
        monitor.onWakeSettled = { noWake.fulfill() }
        monitor.start()
        NotificationCenter.default.post(
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await fulfillment(of: [settled, noWake], timeout: 2)
    }
}
