import AVFoundation
import Darwin
import Foundation
import VideoToolbox

// Compile with the four production Core sources listed in
// docs/NATIVE_LOCK_MEDIA_AUDIT_2026-11-21.md. This is not an app target.
private enum AuditError: Error { case failed(String) }
private func require(_ value: Bool, _ message: String) throws {
    if !value { throw AuditError.failed(message) }
}

@main struct NativeLockMediaAudit {
    static func main() async {
        do { try await run() }
        catch {
            fputs("Native Lock media audit failed: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        try require(CommandLine.arguments.count == 2, "Pass a new output directory inside the system temporary directory")
        let requested = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        // Resolve the existing parent: resolving a nonexistent output leaf can
        // leave /tmp aliases or a symlinked parent unresolved on some runtimes.
        let root = requested.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(requested.lastPathComponent, isDirectory: true)
        let resolved = root.path
        let temporaryRoots = ["/tmp", "/private/tmp",
                              FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path]
        try require(temporaryRoots.contains { path in
            return resolved.hasPrefix(path.hasSuffix("/") ? path : path + "/")
        }, "Output must be inside a temporary directory; no wallpaper-store path is allowed")
        // Exclusive creation: an existing directory is never reused, including
        // one created between the path check and this operation.
        guard mkdir(root.path, 0o700) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let source = root.appendingPathComponent("source.mov")
        try await makeSource(source)
        let legacy = root.appendingPathComponent("legacy-passthrough.mov")
        guard let export = AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough)
        else { throw AuditError.failed("passthrough unavailable") }
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: legacy, as: .mov)
        let plain = root.appendingPathComponent("plain-main10.mov")
        try await encode(source: source, target: plain, temporal: false)
        let temporal = root.appendingPathComponent("temporal-main10.mov")
        try await encode(source: source, target: temporal, temporal: true)
        var reports = [[String: Any]]()
        for url in [legacy, plain, temporal] {
            let asset = AVURLAsset(url: url)
            let track = try await firstVideoTrack(asset)
            let formats = try await track.load(.formatDescriptions)
            guard let format = formats.first else { throw AuditError.failed("missing format description") }
            let codec = CMFormatDescriptionGetMediaSubType(format)
            let fourCC = String(bytes: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: codec >> $0) }, encoding: .ascii) ?? "unknown"
            let duration = try await asset.load(.duration).seconds
            var passes = [[String: Any]]()
            for _ in 0..<3 {
                let reader = try AVAssetReader(asset: asset)
                let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                output.alwaysCopiesSampleData = false
                reader.add(output)
                try require(reader.startReading(), "compressed reader start")
                var count = 0, temporalCount = 0, accessCount = 0
                var levels = Set<Int>()
                while let sample = output.copyNextSampleBuffer() {
                    count += CMSampleBufferGetNumSamples(sample)
                    let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[String: Any]] ?? []
                    for entry in attachments {
                        if let info = entry[kCMSampleAttachmentKey_HEVCTemporalLevelInfo as String] as? [String: Any] {
                            temporalCount += 1
                            if let level = info[kCMHEVCTemporalLevelInfoKey_TemporalLevel as String] as? NSNumber {
                                levels.insert(level.intValue)
                            }
                        }
                        if entry[kCMSampleAttachmentKey_HEVCTemporalSubLayerAccess as String] != nil { accessCount += 1 }
                    }
                }
                try require(reader.status == .completed && count == 60, "compressed EOF/count")
                let decoded = try decode(asset: asset, track: track)
                try require(decoded.frames == 60 && decoded.blackFrames == 0, "decoded EOF/count/nonblack")
                passes.append(["compressedSamples": count, "samplesWithTemporalInfo": temporalCount,
                               "samplesWithSubLayerAccessKey": accessCount, "temporalLevels": levels.sorted(),
                               "decodedFrames": decoded.frames, "blackFrames": decoded.blackFrames])
            }
            reports.append(["file": url.lastPathComponent, "codec": fourCC, "duration": duration,
                            "groupInspector": try AerialTemporalSampleGroups.isPresent(in: url),
                            "passes": passes])
        }
        var scheduling = [[String: Any]]()
        for gap in [0.2, 0.8, 1.99, 2.0, 3.0] {
            var state = NativeLockMaintenanceSchedule()
            state.didUnlock(at: 10)
            let eligibleBeforeLock = state.permitsMaintenance(at: 10 + gap)
            state.cancel() // Same immediate relock callback as AppModel.
            try require(!state.consumeRefresh(), "relock retained refresh")
            state.didUnlock(at: 20)
            try require(!state.permitsMaintenance(at: 20.65), "old deadline bypass")
            try require(state.permitsMaintenance(at: 22) && state.consumeRefresh(), "next unlock recovery")
            try require(!state.consumeRefresh(), "duplicate refresh")
            scheduling.append(["unlockToLockSeconds": gap,
                               "eligibleBeforeRelock": eligibleBeforeLock,
                               "relockCancelledRequest": true, "nextUnlockWaitsFullTwoSeconds": true])
        }
        let report: [String: Any] = ["hostOS": ProcessInfo.processInfo.operatingSystemVersionString,
            "media": reports, "sharedSchedulerModel": scheduling,
            "limitations": ["15/26 routes exercised on the current 27 host, not on those runtimes",
                "AVAssetReader EOF/reopen is not the private wallpaper renderer's loop or ramp-down",
                "No real lock notification, process restart, Apply, Restore or wallpaper-store write"]]
        let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try bytes.write(to: root.appendingPathComponent("report.json"))
        print(String(data: bytes, encoding: .utf8)!)
    }

    private static func firstVideoTrack(_ asset: AVAsset) async throws -> AVAssetTrack {
        guard let track = try await asset.loadTracks(withMediaType: .video).first
        else { throw AuditError.failed("missing video track") }
        return track
    }

    private static func makeSource(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        try require(writer.startWriting(), "source writer start")
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<60 {
            let deadline = Date().addingTimeInterval(10)
            while !input.isReadyForMoreMediaData {
                try require(writer.status == .writing && Date() < deadline, "source writer backpressure")
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            var image: CVPixelBuffer?
            guard let pool = adaptor.pixelBufferPool else { throw AuditError.failed("missing pixel pool") }
            try require(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &image) == kCVReturnSuccess,
                        "source allocation")
            guard let buffer = image else { throw AuditError.failed("missing source buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), Int32(40 + frame), CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            try require(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)), "source append")
        }
        input.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed, "source finish")
    }

    private static func encode(source: URL, target: URL, temporal: Bool) async throws {
        let asset = AVURLAsset(url: source)
        let track = try await firstVideoTrack(asset)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
        output.videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
        reader.add(output)
        if temporal {
            try AerialTemporalEncoder.encode(reader: reader, output: output, destinationURL: target,
                                            width: 320, height: 180, frameRate: 30, duration: 2)
            return
        }
        // The released 26 Main10 settings, at a smaller diagnostic canvas.
        let writer = try AVAssetWriter(outputURL: target, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: 320, AVVideoHeightKey: 180,
            AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true],
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,
                AVVideoMaxKeyFrameIntervalKey: 30, AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
                AVVideoAllowFrameReorderingKey: false,
                AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String]])
        writer.add(input)
        try require(reader.startReading() && writer.startWriting(), "plain writer start")
        writer.startSession(atSourceTime: .zero)
        while let sample = output.copyNextSampleBuffer() {
            let deadline = Date().addingTimeInterval(30)
            while !input.isReadyForMoreMediaData {
                try require(writer.status == .writing && Date() < deadline, "plain writer backpressure")
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            try require(input.append(sample), "plain writer append")
        }
        try require(reader.status == .completed, "plain reader finish")
        input.markAsFinished()
        await writer.finishWriting()
        try require(writer.status == .completed, "plain writer finish")
    }

    private static func decode(asset: AVAsset, track: AVAssetTrack) throws -> (frames: Int, blackFrames: Int) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        try require(reader.startReading(), "decode start")
        var frames = 0, blackFrames = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw AuditError.failed("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            guard let address = CVPixelBufferGetBaseAddress(buffer) else {
                CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
                throw AuditError.failed("missing decoded pixel storage")
            }
            let pixel = address.assumingMemoryBound(to: UInt8.self)
            if pixel[0] < 5 && pixel[1] < 5 && pixel[2] < 5 { blackFrames += 1 }
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            frames += 1
        }
        try require(reader.status == .completed, "decode finish")
        return (frames, blackFrames)
    }
}

