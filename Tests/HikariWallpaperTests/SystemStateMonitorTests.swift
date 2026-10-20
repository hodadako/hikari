import AppKit
import XCTest

@MainActor
final class SystemStateMonitorTests: XCTestCase {
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
