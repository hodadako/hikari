import XCTest
@testable import LuminaCore

final class ScreenSaverIdleTimePolicyTests: XCTestCase {
    func testDisableRestoresTheOriginalDelayExactly() {
        var policy = ScreenSaverIdleTimePolicy()
        XCTAssertEqual(policy.enable(currentIdleTime: 900), 60)
        XCTAssertEqual(policy.originalIdleTime, 900)
        XCTAssertEqual(policy.disable(), 900)
        XCTAssertNil(policy.originalIdleTime)
    }

    func testRepeatedEnableDoesNotOverwriteOriginalDelay() {
        var policy = ScreenSaverIdleTimePolicy()
        _ = policy.enable(currentIdleTime: 300)
        _ = policy.enable(currentIdleTime: 60)
        XCTAssertEqual(policy.disable(), 300)
    }
}
