import AVFoundation
import VideoToolbox
import XCTest
@testable import HikariCore

final class AerialTemporalEncoderTests: XCTestCase {
    func testCacheProfilesDoNotReuseMacOS26Main10DerivativeOn27() {
        XCTAssertEqual(AerialPreparationProfile(operatingSystemMajorVersion: 26).cacheVersion,
                       "aerial-hevc-main10-1920x1080-v1")
        XCTAssertNotEqual(AerialPreparationProfile(operatingSystemMajorVersion: 27).cacheVersion,
                          AerialPreparationProfile(operatingSystemMajorVersion: 26).cacheVersion)
    }

    func testInspectorRequiresDescriptionsAndMappingsOutsideMediaPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TemporalGroups-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.mov")
        let groups = box("sgpd", Data(repeating: 0, count: 4) + Data("tscl".utf8))
            + box("sgpd", Data(repeating: 0, count: 4) + Data("tsas".utf8))
        let maps = box("csgm", Data(repeating: 0, count: 4) + Data("tscl".utf8))
            + box("csgm", Data(repeating: 0, count: 4) + Data("tsas".utf8))
        for bytes in [Data(), box("mdat", groups + maps), box("moov", groups),
                      box("moov", maps), box("moov", Data([0, 0, 0, 255, 97, 98, 99, 100]))] {
            try bytes.write(to: file)
            XCTAssertFalse(try AerialTemporalSampleGroups.isPresent(in: file))
        }
        try box("moov", box("trak", box("mdia", box("minf", box("stbl", groups + maps))))).write(to: file)
        XCTAssertTrue(try AerialTemporalSampleGroups.isPresent(in: file))
    }

    func testGoldenGateEncoderProducesTemporalGroupsPreservesDurationAndDecodes() async throws {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 else {
            throw XCTSkip("Actual temporal output acceptance is checked on macOS 27; 15/26 use the unchanged profile.")
        }
        #if arch(arm64)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TemporalEncode-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mov"), target = root.appendingPathComponent("target.mov")
        try await makeSource(source)
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
        output.videoComposition = AVVideoComposition(propertiesOf: asset)
        reader.add(output)
        do {
            try AerialTemporalEncoder.encode(reader: reader, output: output, destinationURL: target,
                                             width: 320, height: 180, frameRate: 30)
        } catch AerialTemporalEncodingError.videoToolbox(let status) where status == kVTCouldNotFindVideoEncoderErr {
            throw XCTSkip("This 27 runner has no required hardware HEVC encoder; actual temporal acceptance requires a hardware-capable Mac.")
        }
        XCTAssertTrue(try AerialTemporalSampleGroups.isPresent(in: target))
        let encoded = AVURLAsset(url: target)
        let encodedTracks = try await encoded.loadTracks(withMediaType: .video)
        let encodedTrack = try XCTUnwrap(encodedTracks.first)
        let sourceDuration = try await asset.load(.duration).seconds
        let outputDuration = try await encoded.load(.duration).seconds
        XCTAssertEqual(outputDuration, sourceDuration, accuracy: 1.0 / 30)
        let size = try await encodedTrack.load(.naturalSize)
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
        let formats = try await encodedTrack.load(.formatDescriptions)
        XCTAssertEqual(CMFormatDescriptionGetMediaSubType(try XCTUnwrap(formats.first)), kCMVideoCodecType_HEVC)
        let audio = try await encoded.loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
        let decoded = try await AVAssetImageGenerator(asset: encoded).image(at: CMTime(seconds: 0.5, preferredTimescale: 600))
        XCTAssertEqual(decoded.image.width, 320)
        XCTAssertEqual(decoded.image.height, 180)
        let before = try Data(contentsOf: target)
        XCTAssertThrowsError(try AerialTemporalEncoder.encode(reader: reader, output: output, destinationURL: target,
                                                              width: 320, height: 180, frameRate: 30))
        XCTAssertEqual(try Data(contentsOf: target), before)
        #else
        throw XCTSkip("macOS 27 hardware encoding is Apple Silicon only.")
        #endif
    }

    private func box(_ type: String, _ bytes: Data) -> Data {
        var size = UInt32(bytes.count + 8).bigEndian
        return withUnsafeBytes(of: &size) { Data($0) } + Data(type.utf8) + bytes
    }
    private func makeSource(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing, Date() < deadline else { throw AerialTemporalEncodingError.writerFailed }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var image: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, try XCTUnwrap(adaptor.pixelBufferPool), &image), kCVReturnSuccess)
            let buffer = try XCTUnwrap(image)
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(40 + frame), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }
}
