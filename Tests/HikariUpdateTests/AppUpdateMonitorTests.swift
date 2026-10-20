import AppKit
import UserNotifications
import XCTest

@MainActor
final class AppUpdateMonitorTests: XCTestCase {
    func testAutomaticCheckIsThrottledAcrossRelaunchAndRefreshesAfterOneDay() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_000_000)
            var fetches = 0
            var notifications = 0
            let release = self.release("v0.3.6")
            @MainActor func makeMonitor() -> AppUpdateMonitor {
                AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                    fetches += 1
                    return release
                }, notify: { _ in
                    notifications += 1
                    return true
                }, now: { date })
            }
            let monitor = makeMonitor()
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(monitor.state, .updateAvailable)
            XCTAssertEqual(fetches, 1)
            XCTAssertEqual(notifications, 1)

            let relaunched = makeMonitor()
            XCTAssertEqual(relaunched.latestRelease, release)
            XCTAssertTrue(relaunched.hasUpdateAvailable)
            date.addTimeInterval(24 * 3600 - 1)
            XCTAssertNil(relaunched.checkForUpdates(automatically: true))
            date.addTimeInterval(1)
            await relaunched.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(fetches, 2)
            XCTAssertEqual(notifications, 1, "The same release must not produce daily banners")
        }
    }

    func testManualCheckBypassesThrottleWithoutPostingBanner() async {
        await withDefaults { defaults in
            var fetches = 0
            var notifications = 0
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                fetches += 1
                return self.release("v0.3.6")
            }, notify: { _ in
                notifications += 1
                return true
            })
            await monitor.checkForUpdates()?.value
            await monitor.checkForUpdates()?.value
            XCTAssertEqual(fetches, 2)
            XCTAssertEqual(notifications, 0)
            XCTAssertNil(monitor.checkForUpdates(automatically: true))
        }
    }

    func testDeniedNotificationKeepsMenuStateAndCanBeRetriedWhenAuthorized() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_000_000)
            var allowed = false
            var posted = 0
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                self.release("v0.3.6")
            }, notify: { _ in
                if allowed { posted += 1 }
                return allowed
            }, now: { date })
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertTrue(monitor.hasUpdateAvailable)
            XCTAssertEqual(posted, 0)
            date.addTimeInterval(24 * 3600)
            allowed = true
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(posted, 1)
            date.addTimeInterval(24 * 3600)
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(posted, 1)
        }
    }

    func testNewerReleaseNotifiesAgainButInstalledOrOlderReleaseDoesNot() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_000_000)
            var tag = "v0.3.5"
            var notified: [String] = []
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                self.release(tag)
            }, notify: { release in
                notified.append(release.tagName)
                return true
            }, now: { date })
            for nextTag in ["v0.3.5", "v0.3.4", "v0.3.6", "v0.3.7", "v0.3.6"] {
                tag = nextTag
                date.addTimeInterval(24 * 3600)
                await monitor.checkForUpdates(automatically: true)?.value
            }
            XCTAssertEqual(notified, ["v0.3.6", "v0.3.7"])
            let updated = AppUpdateMonitor(currentVersion: "0.3.7", defaults: defaults)
            XCTAssertFalse(updated.hasUpdateAvailable, "Installing the update clears the menu indicator")
        }
    }

    func testOfflineCheckIsQuietAndThrottledButManualRetryShowsError() async {
        await withDefaults { defaults in
            var fetches = 0
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                fetches += 1
                throw URLError(.notConnectedToInternet)
            }, notify: { _ in XCTFail("An offline check cannot notify"); return false })
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(monitor.state, .idle)
            XCTAssertNil(monitor.errorMessage)
            XCTAssertNil(monitor.checkForUpdates(automatically: true))
            await monitor.checkForUpdates()?.value
            XCTAssertEqual(monitor.state, .failed)
            XCTAssertNotNil(monitor.errorMessage)
            XCTAssertEqual(fetches, 2)
        }
    }

    func testNetworkFailureDoesNotEraseKnownUpdate() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_000_000)
            var offline = false
            let release = self.release("v0.3.6")
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                if offline { throw URLError(.timedOut) }
                return release
            }, notify: { _ in true }, now: { date })
            await monitor.checkForUpdates(automatically: true)?.value
            offline = true
            date.addTimeInterval(24 * 3600)
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(monitor.state, .updateAvailable)
            XCTAssertEqual(monitor.latestRelease, release)
            let relaunched = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults)
            XCTAssertTrue(relaunched.hasUpdateAvailable)
        }
    }

    func testInvalidOrIncompleteReleaseNeverBecomesAvailable() async {
        await withDefaults { defaults in
            var release = self.release("invalid")
            var notifications = 0
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                release
            }, notify: { _ in notifications += 1; return true })
            await monitor.checkForUpdates()?.value
            XCTAssertEqual(monitor.state, .failed)
            XCTAssertFalse(monitor.hasUpdateAvailable)
            release = self.release("v0.3.6", withAssets: false)
            await monitor.checkForUpdates()?.value
            XCTAssertEqual(monitor.state, .failed)
            XCTAssertFalse(monitor.hasUpdateAvailable)
            XCTAssertEqual(notifications, 0)
        }
    }

    func testOverlappingChecksShareRequestAndStoppingDiscardsItsResult() async {
        await withDefaults { defaults in
            var fetches = 0
            var response: CheckedContinuation<LatestRelease, Never>?
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                fetches += 1
                return await withCheckedContinuation { response = $0 }
            }, notify: { _ in XCTFail("A stopped check cannot notify"); return false })
            let first = monitor.checkForUpdates()
            let overlapping = monitor.checkForUpdates()
            // Let the request suspend, then stop before delivering its response.
            while response == nil { await Task.yield() }
            monitor.stop()
            response?.resume(returning: self.release("v0.3.6"))
            await first?.value
            await overlapping?.value
            XCTAssertEqual(fetches, 1)
            XCTAssertEqual(monitor.state, .idle)
            XCTAssertNil(monitor.latestRelease)
        }
    }

    func testClockMovingBackwardsDoesNotSuppressChecksIndefinitely() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_000_000)
            var fetches = 0
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                fetches += 1
                return self.release("v0.3.5")
            }, notify: { _ in false }, now: { date })
            await monitor.checkForUpdates(automatically: true)?.value
            date.addTimeInterval(-3600)
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(fetches, 2)
        }
    }

    func testOnlyClickingUpdateNotificationOpensAbout() {
        XCTAssertTrue(UpdateNotificationService.opensUpdates(
            identifier: UpdateNotificationService.identifier,
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
        XCTAssertFalse(UpdateNotificationService.opensUpdates(
            identifier: UpdateNotificationService.identifier,
            actionIdentifier: UNNotificationDismissActionIdentifier
        ))
        XCTAssertFalse(UpdateNotificationService.opensUpdates(
            identifier: "com.hodadako.Hikari.native-lock-ready.example",
            actionIdentifier: UNNotificationDefaultActionIdentifier
        ))
    }

    func testWakeChecksWhenDueAndStopRemovesWakeObserver() async {
        await withDefaults { defaults in
            var date = Date(timeIntervalSince1970: 1_000_000)
            var fetches = 0
            let wakeCheck = self.expectation(description: "Due check after waking")
            wakeCheck.assertForOverFulfill = true
            let monitor = AppUpdateMonitor(currentVersion: "0.3.5", defaults: defaults, fetch: {
                fetches += 1
                if fetches == 2 { wakeCheck.fulfill() }
                return self.release("v0.3.5")
            }, notify: { _ in false }, now: { date })
            monitor.start()
            defer { monitor.stop() }
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(fetches, 1)
            date.addTimeInterval(24 * 3600)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            await self.fulfillment(of: [wakeCheck], timeout: 2)
            await monitor.checkForUpdates(automatically: true)?.value
            XCTAssertEqual(fetches, 2)
            monitor.stop()
            date.addTimeInterval(24 * 3600)
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            // Deliver queued notification callbacks before checking the count.
            await Task.yield()
            XCTAssertEqual(fetches, 2)
        }
    }

    private func withDefaults(_ body: (UserDefaults) async -> Void) async {
        let suite = "HikariUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        await body(defaults)
    }

    private func release(_ tag: String, withAssets: Bool = true) -> LatestRelease {
        LatestRelease(
            tagName: tag, name: tag,
            htmlURL: URL(string: "https://github.com/hodadako/hikari/releases/tag/\(tag)")!,
            assets: withAssets ? [
                ReleaseAsset(name: "Hikari-macOS-portable.zip",
                             browserDownloadURL: URL(string: "https://example.com/app.zip")!, size: 1),
                ReleaseAsset(name: "Hikari-macOS-portable.zip.sha256",
                             browserDownloadURL: URL(string: "https://example.com/app.zip.sha256")!, size: 1)
            ] : []
        )
    }
}
