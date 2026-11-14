import AVFoundation
import Foundation
import VideoToolbox

/// Separate cache identities keep macOS 26 derivatives unchanged. A Main10
/// file alone does not provide 27's temporal sample descriptions.
public enum AerialPreparationProfile: Sendable {
    case main10
    case temporalMain10
    public init(operatingSystemMajorVersion: Int) {
        self = operatingSystemMajorVersion == 27 ? .temporalMain10 : .main10
    }
    public var cacheVersion: String {
        switch self {
        case .main10: "aerial-hevc-main10-1920x1080-v1"
        case .temporalMain10: "aerial-hevc-main10-temporal-1920x1080-v2"
        }
    }
}

public enum AerialTemporalEncodingError: Error {
    case invalidInput
    case videoToolbox(OSStatus)
    case writerFailed
    case missingTemporalGroups
}

/// One-time preparation of a private Native Lock derivative. The caller supplies
/// the existing aspect-fit composition reader; no desktop player is involved.
public enum AerialTemporalEncoder {
    public static func encode(reader: AVAssetReader, output: AVAssetReaderOutput,
                              destinationURL: URL, width: Int, height: Int, frameRate: Int,
                              duration: Double = 0,
                              control: VideoPreparationControl = VideoPreparationControl()) throws {
        try control.checkCancellation()
        guard !FileManager.default.fileExists(atPath: destinationURL.path), width > 0, height > 0, width <= 8192, height <= 8192, frameRate > 1, frameRate <= 240 else {
            throw AerialTemporalEncodingError.invalidInput
        }
        let sink = CompressedMovieSink(destinationURL: destinationURL, control: control)
        var session: VTCompressionSession?
        let createStatus = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
            width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: [kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true] as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: { context, _, status, flags, sample in
                guard let context else { return }
                Unmanaged<CompressedMovieSink>.fromOpaque(context).takeUnretainedValue()
                    .receive(status: status, flags: flags, sample: sample)
            }, refcon: Unmanaged.passUnretained(sink).toOpaque(), compressionSessionOut: &session)
        guard createStatus == noErr, let session else {
            throw AerialTemporalEncodingError.videoToolbox(createStatus)
        }
        var completed = false
        defer {
            VTCompressionSessionInvalidate(session)
            if !completed {
                reader.cancelReading()
                sink.cancel()
                // The caller owns its private staging directory. Do not unlink
                // a path that another writer may have created or replaced.
            }
            withExtendedLifetime(sink) {}
        }
        // Public VideoToolbox property: requests hierarchical HEVC encoding.
        // No undocumented NumberOfTemporalLayers key or file patching is used.
        let properties: [CFString: Any] = [
            kVTCompressionPropertyKey_ProfileLevel: kVTProfileLevel_HEVC_Main10_AutoLevel,
            kVTCompressionPropertyKey_AverageBitRate: 12_000_000,
            kVTCompressionPropertyKey_ExpectedFrameRate: frameRate,
            kVTCompressionPropertyKey_BaseLayerFrameRate: Double(frameRate) / 2,
            kVTCompressionPropertyKey_AllowFrameReordering: false,
            kVTCompressionPropertyKey_RealTime: false,
            kVTCompressionPropertyKey_MaxKeyFrameInterval: frameRate,
            kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration: 1.0,
            kVTCompressionPropertyKey_ColorPrimaries: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kVTCompressionPropertyKey_TransferFunction: kCVImageBufferTransferFunction_ITU_R_709_2,
            kVTCompressionPropertyKey_YCbCrMatrix: kCVImageBufferYCbCrMatrix_ITU_R_709_2
        ]
        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
            guard status == noErr else { throw AerialTemporalEncodingError.videoToolbox(status) }
        }
        let prepared = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepared == noErr else { throw AerialTemporalEncodingError.videoToolbox(prepared) }
        guard reader.startReading() else { throw reader.error ?? AerialTemporalEncodingError.invalidInput }
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            try control.checkCancellation()
            try sink.checkFailure()
            guard let image = CMSampleBufferGetImageBuffer(sample) else { throw AerialTemporalEncodingError.invalidInput }
            let status = VTCompressionSessionEncodeFrame(session, imageBuffer: image,
                presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sample),
                duration: CMSampleBufferGetDuration(sample), frameProperties: nil,
                sourceFrameRefcon: nil, infoFlagsOut: nil)
            guard status == noErr else { throw AerialTemporalEncodingError.videoToolbox(status) }
            frames += 1
            if duration > 0 {
                control.reportProgress(min(0.95, CMSampleBufferGetPresentationTimeStamp(sample).seconds / duration * 0.95))
            }
        }
        try control.checkCancellation()
        guard reader.status == .completed, frames > 0 else {
            throw reader.error ?? AerialTemporalEncodingError.invalidInput
        }
        let flushed = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard flushed == noErr else { throw AerialTemporalEncodingError.videoToolbox(flushed) }
        try sink.finish(expectedFrames: frames)
        try control.checkCancellation()
        guard try AerialTemporalSampleGroups.isPresent(in: destinationURL) else {
            throw AerialTemporalEncodingError.missingTemporalGroups
        }
        completed = true
    }
}

/// VideoToolbox callbacks own writer access under this lock. The producer only
/// reads failures; finish runs after CompleteFrames has drained every callback.
private final class CompressedMovieSink: @unchecked Sendable {
    private let destinationURL: URL
    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var failure: Error?
    private var frames = 0
    private let control: VideoPreparationControl
    init(destinationURL: URL, control: VideoPreparationControl) {
        self.destinationURL = destinationURL
        self.control = control
    }

    func receive(status: OSStatus, flags: VTEncodeInfoFlags, sample: CMSampleBuffer?) {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil else { return }
        do {
            try control.checkCancellation()
            guard status == noErr else { throw AerialTemporalEncodingError.videoToolbox(status) }
            guard !flags.contains(.frameDropped), let sample, CMSampleBufferDataIsReady(sample),
                  let format = CMSampleBufferGetFormatDescription(sample) else {
                throw AerialTemporalEncodingError.invalidInput
            }
            if writer == nil {
                let movie = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
                movie.shouldOptimizeForNetworkUse = true
                let track = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
                track.expectsMediaDataInRealTime = false
                guard movie.canAdd(track) else { throw AerialTemporalEncodingError.writerFailed }
                movie.add(track)
                guard movie.startWriting() else { throw movie.error ?? AerialTemporalEncodingError.writerFailed }
                movie.startSession(atSourceTime: .zero)
                writer = movie; input = track
            }
            guard let writer, let input else { throw AerialTemporalEncodingError.writerFailed }
            let deadline = DispatchTime.now() + .seconds(30)
            while !input.isReadyForMoreMediaData {
                try control.checkCancellation()
                guard writer.status == .writing, DispatchTime.now() < deadline else {
                    throw writer.error ?? AerialTemporalEncodingError.writerFailed
                }
                Thread.sleep(forTimeInterval: 0.001)
            }
            guard input.append(sample) else { throw writer.error ?? AerialTemporalEncodingError.writerFailed }
            frames += 1
        } catch { failure = error }
    }

    func checkFailure() throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
    }
    func finish(expectedFrames: Int) throws {
        try checkFailure()
        guard frames == expectedFrames, let writer, let input else { throw AerialTemporalEncodingError.writerFailed }
        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        let deadline = DispatchTime.now() + .seconds(60)
        while finished.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            try control.checkCancellation()
            guard DispatchTime.now() < deadline else { throw AerialTemporalEncodingError.writerFailed }
        }
        try control.checkCancellation()
        guard writer.status == .completed else {
            throw writer.error ?? AerialTemporalEncodingError.writerFailed
        }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        writer?.cancelWriting()
    }
}
