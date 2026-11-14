import XCTest
@testable import HikariCore

final class NativeLockMaintenanceScheduleTests: XCTestCase {
    func testStartupRequestsOnlyOneRefresh() {
        var state = NativeLockMaintenanceSchedule()
        state.requestRefresh()
        XCTAssertTrue(state.permitsMaintenance(at: 0))
        XCTAssertTrue(state.consumeRefresh())
        XCTAssertFalse(state.consumeRefresh())
    }

    func testPeriodicTickCannotConsumePreviousRequestDuringNewUnlockDelay() {
        var state = NativeLockMaintenanceSchedule()
        state.didUnlock(at: 10)
        // An old timer elapsed while locked; the next unlock must supersede it.
        state.didUnlock(at: 20)
        XCTAssertTrue(state.refreshRequested)
        XCTAssertFalse(state.permitsMaintenance(at: 20.65))
        XCTAssertFalse(state.permitsMaintenance(at: 21.999))
        XCTAssertTrue(state.permitsMaintenance(at: 22))
        XCTAssertTrue(state.consumeRefresh())
        XCTAssertFalse(state.consumeRefresh())
    }

    func testTransientFailureDoesNotRemoveUnlockDeadline() {
        var state = NativeLockMaintenanceSchedule()
        state.requestRefresh()
        XCTAssertTrue(state.consumeRefresh())
        state.didUnlock(at: 30)
        // A previous asynchronous pass failed after the new unlock arrived.
        state.requestRefresh()
        XCTAssertFalse(state.permitsMaintenance(at: 31))
        XCTAssertTrue(state.permitsMaintenance(at: 32))
    }

    func testRelockAndStopDiscardPendingWork() {
        var state = NativeLockMaintenanceSchedule()
        state.didUnlock(at: 10)
        state.cancel()
        XCTAssertFalse(state.consumeRefresh())
        state.didUnlock(at: 11)
        XCTAssertFalse(state.permitsMaintenance(at: 12))
        XCTAssertTrue(state.permitsMaintenance(at: 13))
        state.cancel()
        XCTAssertFalse(state.refreshRequested)
    }
}
