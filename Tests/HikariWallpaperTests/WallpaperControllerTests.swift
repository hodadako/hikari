import AppKit
import AVFoundation
import HikariCore
import XCTest

/// These integration tests need WindowServer and run in the Xcode scheme.
/// SwiftPM's core tests alone cannot exercise AVPlayerLayer presentation.
@MainActor
final class WallpaperControllerTests: XCTestCase {
    private var controller: WallpaperController!
    private var directory: URL!

    override func setUp() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else {
            throw XCTSkip("A WindowServer display is required")
        }
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        controller = WallpaperController()
    }

    override func tearDown() async throws {
        controller?.closeWindows()
        controller = nil
        if let directory {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testRepeatedRecoveryKeepsReadyWindowsAndSharedPlayback() async throws {
        let player = try await preparePlayback()
        let item = player.currentItem
        let count = NSScreen.screens.count
        var previousWindows = Set(windows.map(\.windowNumber))

        for _ in 0..<20 {
            controller.rebuildWindowsIfContentAvailable(true)
            // The regression closed the ready windows synchronously and
            // replaced them with black windows, then sought the shared player.
            XCTAssertTrue(previousWindows.isSubset(of: Set(windows.map(\.windowNumber))))
            XCTAssertGreaterThanOrEqual(readyWindows.count, count)
            try await waitForHandoff(replacing: previousWindows, count: count)
            XCTAssertTrue(layers.allSatisfy { $0.player === player })
            XCTAssertTrue(player.currentItem === item)
            XCTAssertGreaterThan(player.rate, 0)
            XCTAssertTrue(player.isMuted)
            previousWindows = Set(windows.map(\.windowNumber))
        }
    }

    func testPausedRecoveryDoesNotSeekOrResume() async throws {
        let player = try await preparePlayback()
        controller.pause()
        let position = player.currentTime()
        let noSeek = XCTNSNotificationExpectation(
            name: AVPlayerItem.timeJumpedNotification,
            object: player.currentItem
        )
        noSeek.isInverted = true
        let previousWindows = Set(windows.map(\.windowNumber))
        controller.rebuildWindowsIfContentAvailable(true)
        try await waitForHandoff(replacing: previousWindows, count: NSScreen.screens.count)
        XCTAssertEqual(player.rate, 0)
        // AVPlayer's pause can settle a fraction of a millisecond after the
        // call on macOS 15 Intel. Preserve the displayed 30fps source frame,
        // and separately reject actual time jumps rather than comparing raw
        // nanosecond clocks for exact equality.
        XCTAssertEqual(player.currentTime().seconds, position.seconds, accuracy: 1.0 / 30)
        await fulfillment(of: [noSeek], timeout: 0.1)
        XCTAssertFalse(controller.isPlaying)
    }

    func testOverlappingRecoveryIsBoundedAndScalingStaysCurrent() async throws {
        let player = try await preparePlayback()
        let previousWindows = Set(windows.map(\.windowNumber))
        for _ in 0..<30 {
            controller.rebuildWindowsIfContentAvailable(true)
            controller.refreshWindowsForActiveSpaceIfContentAvailable(true)
        }
        XCTAssertEqual(windows.count, NSScreen.screens.count * 2)
        controller.setScalingMode(.fit)
        XCTAssertTrue(layers.allSatisfy { $0.videoGravity == .resizeAspect })
        try await waitForHandoff(replacing: previousWindows, count: NSScreen.screens.count)
        XCTAssertTrue(layers.allSatisfy { $0.player === player })
        controller.setScalingMode(.fill)
        XCTAssertTrue(layers.allSatisfy { $0.videoGravity == .resizeAspectFill })
    }

    func testCloseCancelsPendingRecovery() async throws {
        _ = try await preparePlayback()
        controller.rebuildWindowsIfContentAvailable(true)
        controller.closeWindows()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(windows.isEmpty)
        XCTAssertFalse(controller.isPlaying)
    }

    func testContentRemovalCancelsPendingRecovery() async throws {
        let player = try await preparePlayback()
        let previousWindows = Set(windows.map(\.windowNumber))
        controller.rebuildWindowsIfContentAvailable(true)
        controller.setContent(url: nil, muted: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(Set(windows.map(\.windowNumber)), previousWindows)
        XCTAssertNil(player.currentItem)
    }

    func testUnreadyReplacementTimesOutWithoutClosingOriginal() async throws {
        // An unreadable item never produces a ready AVPlayerLayer. The
        // deadline must discard only replacements, never promote them.
        controller.setContentAvailable(true)
        controller.setContent(url: directory.appendingPathComponent("missing.mov"), muted: true)
        let previousWindows = Set(windows.map(\.windowNumber))
        controller.rebuildWindowsIfContentAvailable(true)
        XCTAssertEqual(windows.count, previousWindows.count * 2)
        try await Task.sleep(for: .milliseconds(3300))
        XCTAssertEqual(Set(windows.map(\.windowNumber)), previousWindows)
    }

    private var windows: [NSWindow] {
        NSApplication.shared.windows.filter { window in
            window.isVisible && playerLayer(in: window) != nil
        }
    }

    private var readyWindows: [NSWindow] {
        windows.filter { playerLayer(in: $0)?.isReadyForDisplay == true }
    }

    private var layers: [AVPlayerLayer] {
        windows.compactMap { playerLayer(in: $0) }
    }

    private func playerLayer(in window: NSWindow) -> AVPlayerLayer? {
        window.contentView?.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.first
    }

    private func waitForHandoff(replacing previous: Set<Int>, count: Int) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            // Every display must retain a ready surface throughout recovery.
            XCTAssertGreaterThanOrEqual(readyWindows.count, count)
            if windows.count == count,
               previous.isDisjoint(with: Set(windows.map(\.windowNumber))) {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Replacement surfaces did not become ready and retire the old windows")
    }

    private func preparePlayback() async throws -> AVPlayer {
        let url = directory.appendingPathComponent("bright.mov")
        try await makeVideo(at: url)
        controller.setContentAvailable(true)
        controller.setContent(url: url, muted: true)
        controller.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while readyWindows.count != NSScreen.screens.count || !controller.isPlaying {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "WallpaperTests", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Initial video did not become ready"])
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(layers.first?.player)
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 320,
            AVVideoHeightKey: 180
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,
            try XCTUnwrap(adaptor.pixelBufferPool), &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        // A bright frame makes a black surface unambiguous in visual captures.
        memset(CVPixelBufferGetBaseAddress(buffer), 220,
               CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        // Allow the 20-recovery test to run on slower CI hosts without a
        // natural loop changing currentItem during the identity assertions.
        for frame in 0..<1800 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw try XCTUnwrap(writer.error) }
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
