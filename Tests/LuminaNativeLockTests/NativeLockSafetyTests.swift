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
        XCTAssertEqual(
            report.detail,
            "The selected video remains in Hikari's private application-support directory."
        )
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

    func testReportsMacOS26UserAerialPathAsReady() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 26,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true
        )

        XCTAssertEqual(report.state, .ready)
        XCTAssertEqual(
            report.detail,
            "Applying uses the verified macOS 26 user Aerial catalog and creates rollback records without administrator approval."
        )
    }

    func testActiveReportUsesHikariProductName() {
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            transactionPhase: .active
        )

        XCTAssertEqual(report.state, .active)
        XCTAssertEqual(
            report.detail,
            "The macOS-owned Lock Screen uses the staged Hikari video."
        )
    }

    func testUnfinishedTransactionRequiresRestoreBeforeMajorOSUpdate() {
        XCTAssertTrue(
            NativeLockUpgradeGuard
                .requiresRestoreBeforeMajorOperatingSystemUpdate(
                    transactionPhase: .active
                )
        )
        XCTAssertTrue(
            NativeLockUpgradeGuard
                .requiresRestoreBeforeMajorOperatingSystemUpdate(
                    transactionPhase: .recoveryRequired
                )
        )
        XCTAssertFalse(
            NativeLockUpgradeGuard
                .requiresRestoreBeforeMajorOperatingSystemUpdate(
                    transactionPhase: .restored
                )
        )
        XCTAssertFalse(
            NativeLockUpgradeGuard
                .requiresRestoreBeforeMajorOperatingSystemUpdate(
                    transactionPhase: nil
                )
        )
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
