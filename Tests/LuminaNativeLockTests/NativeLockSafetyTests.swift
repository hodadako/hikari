import XCTest
@testable import LuminaNativeLock

final class NativeLockSafetyTests: XCTestCase {
    func testRejectsUnsupportedOperatingSystem() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 14,
                minorVersion: 6,
                patchVersion: 0
            ),
            hasSelectedMedia: true
        )

        XCTAssertEqual(report.state, .unsupportedOperatingSystem)
    }

    func testRejectsUnreviewedFutureOperatingSystem() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 16,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true
        )

        XCTAssertEqual(report.state, .unsupportedOperatingSystem)
    }

    func testRequiresSelectedMedia() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: false
        )

        XCTAssertEqual(report.state, .mediaRequired)
    }

    func testReportsReadyWhenPrerequisitesArePresent() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true
        )

        XCTAssertEqual(report.state, .ready)
    }

    func testReportsRecoveryRequired() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            transactionPhase: .recoveryRequired
        )

        XCTAssertEqual(report.state, .recoveryRequired)
    }

    func testRecoveryTakesPriorityOverMissingSelectedMedia() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: false,
            transactionPhase: .recoveryRequired
        )

        XCTAssertEqual(report.state, .recoveryRequired)
    }

    func testInterruptedPreparedTransactionRequiresRecovery() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            transactionPhase: .prepared
        )

        XCTAssertEqual(report.state, .recoveryRequired)
    }
}
