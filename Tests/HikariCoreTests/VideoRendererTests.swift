import AVFoundation
import XCTest
@testable import HikariCore

@MainActor
final class VideoRendererTests: XCTestCase {

    func testNoSelectedContentDoesNotRequireRecovery() {
        let renderer = VideoRenderer()

        XCTAssertFalse(renderer.requiresPlaybackRecovery)
    }

    func testMissingQueueItemRequiresRecoveryAndReloadsSelectedContent() async throws {
        let videoURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hikari-renderer-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try await makeVideo(at: videoURL)
        let renderer = VideoRenderer()
        defer { renderer.stopAndRelease() }
        renderer.load(url: videoURL, muted: true)
        XCTAssertFalse(renderer.requiresPlaybackRecovery,
                       "Asynchronous initial preparation must not trigger a reload")
        try await waitForItem(renderer)
        XCTAssertNotNil(renderer.player.currentItem)
        XCTAssertFalse(renderer.requiresPlaybackRecovery)

        renderer.player.removeAllItems()

        XCTAssertNil(renderer.player.currentItem)
        XCTAssertFalse(renderer.requiresPlaybackRecovery,
                       "A transient empty queue must not trigger immediate recovery")
        let recoveryDeadline = ContinuousClock.now.advanced(by: .seconds(7))
        while !renderer.requiresPlaybackRecovery && ContinuousClock.now < recoveryDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(renderer.requiresPlaybackRecovery,
                      "A persistently empty queue must trigger recovery after the grace period")

        renderer.reloadCurrentItem()
        try await waitForItem(renderer)

        XCTAssertEqual(renderer.currentURL, videoURL)
        XCTAssertNotNil(renderer.player.currentItem)
        XCTAssertFalse(renderer.requiresPlaybackRecovery)
        XCTAssertTrue(renderer.player.isMuted)
        XCTAssertEqual(renderer.player.rate, 0)
        renderer.stopAndRelease()
        XCTAssertFalse(renderer.requiresPlaybackRecovery)
    }

    func testFailedMediaRequiresRecoveryWithoutTemplateFailureNotification() async throws {
        let renderer = VideoRenderer()
        defer { renderer.stopAndRelease() }
        renderer.load(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).mov"), muted: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !renderer.requiresPlaybackRecovery && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(renderer.requiresPlaybackRecovery)
    }

    private func waitForItem(_ renderer: VideoRenderer) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while renderer.player.currentItem?.status != .readyToPlay {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "VideoRendererTests", code: 1)
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64, AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64,
                kCVPixelBufferHeightKey as String: 64
            ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var optionalBuffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil,
            try XCTUnwrap(adaptor.pixelBufferPool), &optionalBuffer), kCVReturnSuccess)
        let buffer = try XCTUnwrap(optionalBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 220,
               CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw try XCTUnwrap(writer.error) }
                try await Task.sleep(for: .milliseconds(1))
            }
            XCTAssertTrue(adaptor.append(buffer,
                withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
