import XCTest
@testable import HikariNativeLock

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

    func testReportsMacOS26UserAerialPathAsReady() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appendingPathComponent("entries.json")
        let manifest: [String: Any] = [
            "version": 1,
            "assets": [[String: Any]](),
            "categories": [[String: Any]]()
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)

        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 26,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            aerialManifestURL: manifestURL
        )

        XCTAssertEqual(report.state, .ready)
        XCTAssertEqual(
            report.detail,
            "Applying uses the verified macOS 26 user Aerial catalog and creates rollback records without administrator approval."
        )
    }

    func testMacOS26MissingAerialCatalogReportsAerialCatalogRequired() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let missingManifestURL = dir.appendingPathComponent("entries.json")
        // File intentionally not created.

        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 26,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            aerialManifestURL: missingManifestURL
        )

        XCTAssertEqual(report.state, .aerialCatalogRequired)
        XCTAssertEqual(report.title, "Initialize Apple Aerial wallpapers first")
    }

    func testMacOS26MalformedAerialManifestReportsAerialCatalogRequired() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appendingPathComponent("entries.json")
        // Write a JSON object that is missing required fields.
        try Data("{\"version\":2}".utf8).write(to: manifestURL)

        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 26,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            aerialManifestURL: manifestURL
        )

        XCTAssertEqual(report.state, .aerialCatalogRequired)
        XCTAssertEqual(report.title, "Aerial wallpaper store is not recognized")
    }

    func testMacOS15IgnoresAerialCatalogCheck() {
        // macOS 15 uses the legacy system catalog; the Aerial manifest URL
        // should be irrelevant and the state should be ready.
        let report = NativeLockSafetyInspector.evaluate(
            operatingSystemVersion: OperatingSystemVersion(
                majorVersion: 15,
                minorVersion: 0,
                patchVersion: 0
            ),
            hasSelectedMedia: true,
            aerialManifestURL: nil
        )

        XCTAssertEqual(report.state, .ready)
    }

    func testAerialManifestStateReturnsReadyForValidManifest() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appendingPathComponent("entries.json")
        let manifest: [String: Any] = [
            "version": 1,
            "assets": [[String: Any]](),
            "categories": [[String: Any]]()
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)

        XCTAssertEqual(
            NativeLockSafetyInspector.aerialManifestState(manifestURL: manifestURL),
            .ready
        )
    }

    func testAerialManifestStateReturnsMissingWhenFileAbsent() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("entries.json")

        XCTAssertEqual(
            NativeLockSafetyInspector.aerialManifestState(manifestURL: url),
            .missing
        )
    }

    func testAerialManifestStateReturnsInvalidForBadSchema() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appendingPathComponent("entries.json")
        try Data("not json".utf8).write(to: manifestURL)

        XCTAssertEqual(
            NativeLockSafetyInspector.aerialManifestState(manifestURL: manifestURL),
            .invalid
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

    func testMacOS26LegacyHelperPreflightFailureCanBeDiscarded() {
        let journal = NativeLockJournal(
            transactionID: UUID(),
            assetID: UUID(),
            phase: .recoveryRequired,
            originalWallpaperIndexSHA256: String(repeating: "a", count: 64),
            lastError: NativeLockRecovery.macOS26LegacyHelperFailure
        )

        XCTAssertTrue(
            NativeLockRecovery.canDiscardKnownNoopLegacyPreflight(
                journal,
                operatingSystemMajorVersion: 26
            )
        )
    }

    func testLegacyTransactionWithAppliedMappingCannotBeDiscarded() {
        let journal = NativeLockJournal(
            transactionID: UUID(),
            assetID: UUID(),
            phase: .recoveryRequired,
            originalWallpaperIndexSHA256: String(repeating: "a", count: 64),
            appliedWallpaperIndexSHA256: String(repeating: "b", count: 64),
            lastError: NativeLockRecovery.macOS26LegacyHelperFailure
        )

        XCTAssertFalse(
            NativeLockRecovery.canDiscardKnownNoopLegacyPreflight(
                journal,
                operatingSystemMajorVersion: 26
            )
        )
    }
}
