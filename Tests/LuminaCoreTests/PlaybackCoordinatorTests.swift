import XCTest
@testable import LuminaCore

@MainActor
final class PlaybackCoordinatorTests: XCTestCase {
    @MainActor
    private final class MockSession: PlaybackSession {
        var currentURL: URL?
        var isPlaying = false
        var currentTime = 0.0
        var hasPlaybackError = false
        var loadCount = 0
        var releaseCount = 0
        var seekCount = 0
        var muted = true

        func load(url: URL, muted: Bool) {
            currentURL = url
            self.muted = muted
            loadCount += 1
        }

        func setMuted(_ muted: Bool) { self.muted = muted }
        func play() { isPlaying = true }
        func pause() { isPlaying = false }
        func seek(to seconds: Double) {
            currentTime = seconds
            seekCount += 1
        }
        func releaseResources() {
            currentURL = nil
            isPlaying = false
            releaseCount += 1
        }
    }

    private let videoURL = URL(fileURLWithPath: "/tmp/ocean.mp4")

    func testLoadPlayAndPauseReachEveryDisplay() {
        let coordinator = PlaybackCoordinator()
        let first = MockSession()
        let second = MockSession()
        coordinator.addSession(id: 1, session: first)
        coordinator.addSession(id: 2, session: second)

        coordinator.setContent(url: videoURL, muted: true)
        coordinator.play()
        XCTAssertEqual(first.loadCount, 1)
        XCTAssertEqual(second.loadCount, 1)
        XCTAssertTrue(first.isPlaying)
        XCTAssertTrue(second.isPlaying)

        coordinator.pause()
        XCTAssertFalse(first.isPlaying)
        XCTAssertFalse(second.isPlaying)
    }

    func testUnmutedPlaybackElectsExactlyOneAudioOwner() {
        let coordinator = PlaybackCoordinator()
        let first = MockSession()
        let second = MockSession()
        let third = MockSession()
        coordinator.addSession(id: 3, session: third)
        coordinator.addSession(id: 1, session: first)
        coordinator.addSession(id: 2, session: second)
        coordinator.setContent(url: videoURL, muted: false)

        XCTAssertEqual(coordinator.audioOwnerID, 1)
        XCTAssertFalse(first.muted)
        XCTAssertTrue(second.muted)
        XCTAssertTrue(third.muted)
    }

    func testRemovedDisplayIsReleasedAndNewDisplayGetsCurrentState() {
        let coordinator = PlaybackCoordinator()
        let first = MockSession()
        let second = MockSession()
        coordinator.addSession(id: 1, session: first)
        coordinator.setContent(url: videoURL, muted: true)
        coordinator.play()
        coordinator.removeSession(id: 1)
        XCTAssertEqual(first.releaseCount, 1)

        coordinator.addSession(id: 2, session: second)
        XCTAssertEqual(second.loadCount, 1)
        XCTAssertTrue(second.isPlaying)
    }

    func testSameContentDoesNotReloadEveryPolicyChange() {
        let coordinator = PlaybackCoordinator()
        let session = MockSession()
        coordinator.addSession(id: 1, session: session)
        coordinator.setContent(url: videoURL, muted: true)
        coordinator.play()
        coordinator.pause()
        coordinator.play()
        coordinator.setMuted(false)
        XCTAssertEqual(session.loadCount, 1)
    }

    func testContentChangeReleasesThePreviousSessionBeforeLoading() {
        let coordinator = PlaybackCoordinator()
        let session = MockSession()
        coordinator.addSession(id: 1, session: session)
        coordinator.setContent(url: videoURL, muted: true)
        let secondURL = URL(fileURLWithPath: "/tmp/forest.mp4")
        coordinator.setContent(url: secondURL, muted: true)
        XCTAssertEqual(session.releaseCount, 1)
        XCTAssertEqual(session.currentURL, secondURL)
        XCTAssertEqual(session.loadCount, 2)
    }

    func testDriftCorrectionOnlySeeksOutliers() {
        let coordinator = PlaybackCoordinator(driftTolerance: 0.25)
        let leader = MockSession()
        let close = MockSession()
        let drifted = MockSession()
        coordinator.addSession(id: 1, session: leader)
        coordinator.addSession(id: 2, session: close)
        coordinator.addSession(id: 3, session: drifted)
        coordinator.setContent(url: videoURL, muted: true)
        coordinator.play()
        leader.currentTime = 10
        close.currentTime = 10.1
        drifted.currentTime = 12
        coordinator.synchronizeDrift()
        XCTAssertEqual(close.seekCount, 0)
        XCTAssertEqual(drifted.seekCount, 1)
        XCTAssertEqual(drifted.currentTime, 10)
    }
}
