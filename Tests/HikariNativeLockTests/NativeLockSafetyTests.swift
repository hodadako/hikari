import XCTest
@testable import HikariNativeLock

final class NativeLockSafetyTests: XCTestCase {
    func testShippedPolicyEnables27WithoutAdoptingOtherOSJournals() {
        XCTAssertTrue(NativeLockOperatingSystemPolicy.goldenGateNativeLockEnabled)
        let policy = NativeLockOperatingSystemPolicy(majorVersion: 27)
        XCTAssertEqual(policy.writeBackend, .userAerials27)
        XCTAssertTrue(policy.canModifyTransaction(backend: .userAerials27, operatingSystemMajorVersion: 27))
        for sourceOS: Int? in [nil, 15, 26, 28] {
            XCTAssertFalse(policy.canModifyTransaction(backend: .userAerials27, operatingSystemMajorVersion: sourceOS))
        }
        XCTAssertFalse(policy.canModifyTransaction(backend: .userAerials, operatingSystemMajorVersion: 26))
        XCTAssertTrue(policy.requiresUpgradeRestore(backend: .userAerials, operatingSystemMajorVersion: 26))
        XCTAssertNil(NativeLockOperatingSystemPolicy(majorVersion: 28).writeBackend)
        XCTAssertEqual(NativeLockOperatingSystemPolicy(majorVersion: 15).writeBackend, .systemCatalog)
        XCTAssertEqual(NativeLockOperatingSystemPolicy(majorVersion: 26).writeBackend, .userAerials)
    }

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

    /// Checks backend compatibility, including old journals and unsupported runtimes.
    func testWritePolicyMatchesTheTransactionBackend() {
        let sequoia = NativeLockOperatingSystemPolicy(majorVersion: 15)
        XCTAssertEqual(sequoia.writeBackend, .systemCatalog)
        XCTAssertTrue(sequoia.canModifyTransaction(backend: nil))
        XCTAssertTrue(sequoia.canModifyTransaction(backend: .systemCatalog))
        XCTAssertFalse(sequoia.canModifyTransaction(backend: .userAerials))

        let tahoe = NativeLockOperatingSystemPolicy(majorVersion: 26)
        XCTAssertEqual(tahoe.writeBackend, .userAerials)
        XCTAssertTrue(tahoe.canModifyTransaction(backend: .userAerials))
        XCTAssertFalse(tahoe.canModifyTransaction(backend: nil))
        XCTAssertFalse(tahoe.canModifyTransaction(backend: .systemCatalog))

        let goldenGate = NativeLockOperatingSystemPolicy(majorVersion: 27, goldenGateNativeLockEnabled: true)
        XCTAssertEqual(goldenGate.writeBackend, .userAerials27)
        XCTAssertTrue(goldenGate.canModifyTransaction(backend: .userAerials27, operatingSystemMajorVersion: 27))
        for backend: NativeLockTransactionBackend? in [nil, .systemCatalog, .userAerials] {
            XCTAssertFalse(goldenGate.canModifyTransaction(backend: backend))
        }
        XCTAssertFalse(tahoe.canModifyTransaction(backend: .userAerials, operatingSystemMajorVersion: 27))
    }

    /// Verifies a recognized fixture manifest cannot enable writes on an unreviewed OS
    /// and all unfinished phases remain visible as preserved transactions.
    func testFutureOSPreservesUnfinishedTransactionsEvenWithRecognizedManifest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifestURL = directory.appendingPathComponent("entries.json")
        try Data(#"{"version":1,"assets":[],"categories":[]}"#.utf8).write(to: manifestURL)
        let goldenGate = OperatingSystemVersion(majorVersion: 28, minorVersion: 0, patchVersion: 0)
        XCTAssertEqual(NativeLockSafetyInspector.aerialManifestState(manifestURL: manifestURL), .ready)

        for phase: NativeLockTransactionPhase? in [nil, .restored] {
            let report = NativeLockSafetyInspector.evaluate(
                operatingSystemVersion: goldenGate,
                hasSelectedMedia: true,
                transactionPhase: phase,
                aerialManifestURL: manifestURL
            )
            XCTAssertEqual(report.state, .unsupportedOperatingSystem)
        }

        for phase: NativeLockTransactionPhase in [
            .prepared, .systemApplied, .active, .restoring, .recoveryRequired
        ] {
            let report = NativeLockSafetyInspector.evaluate(
                operatingSystemVersion: goldenGate,
                hasSelectedMedia: false,
                transactionPhase: phase,
                transactionBackend: .userAerials,
                aerialManifestURL: manifestURL
            )
            XCTAssertEqual(report.state, .transactionPreserved)
        }
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
            "Applying uses the verified user Aerial catalog and creates rollback records without administrator approval."
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

    /// Rejects corrupt JSON, future schemas, Boolean versions and malformed arrays.
    func testAerialManifestStateReturnsInvalidForBadSchema() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let manifestURL = dir.appendingPathComponent("entries.json")
        for manifest in [
            "not json",
            #"{"version":2,"assets":[],"categories":[]}"#,
            #"{"version":true,"assets":[],"categories":[]}"#,
            #"{"version":1,"assets":[null],"categories":[]}"#
        ] {
            try Data(manifest.utf8).write(to: manifestURL)
            XCTAssertEqual(
                NativeLockSafetyInspector.aerialManifestState(manifestURL: manifestURL),
                .invalid
            )
        }
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
