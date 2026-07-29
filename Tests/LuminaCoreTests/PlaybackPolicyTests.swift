import XCTest
@testable import LuminaCore

final class PlaybackPolicyTests: XCTestCase {
    func testPlayingRequiresContentAndNoPauseReason() {
        var policy = PlaybackPolicy(hasContent: true)
        XCTAssertTrue(policy.shouldPlay)
        XCTAssertTrue(policy.pauseReasons.isEmpty)

        policy.isSleeping = true
        XCTAssertFalse(policy.shouldPlay)
        XCTAssertEqual(policy.pauseReasons, [.sleep])
    }

    func testUserPauseIsNotClearedBySystemResume() {
        let policy = PlaybackPolicy(
            userWantsPlayback: false,
            isScreenLocked: false,
            isSleeping: false,
            hasContent: true
        )
        XCTAssertFalse(policy.shouldPlay)
        XCTAssertEqual(policy.pauseReasons, [.user])
    }

    func testAllIndependentPauseReasonsAreRetained() {
        let policy = PlaybackPolicy(
            userWantsPlayback: false,
            pauseOnBattery: true,
            isOnBattery: true,
            isScreenLocked: true,
            isScreenSaverRunning: true,
            isSleeping: true,
            hasContent: false
        )
        XCTAssertEqual(
            policy.pauseReasons,
            [.user, .battery, .screenLock, .screenSaver, .sleep, .noContent]
        )
    }
}
