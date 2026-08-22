#if LUMINA_NATIVE_LOCAL
import AppKit
import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import LuminaCore
import LuminaNativeLock
import OSLog
import UniformTypeIdentifiers
import VideoToolbox

private let nativeLockLogger = Logger(
    subsystem: "com.hodadako.Lumina.NativeLocal",
    category: "NativeLock"
)

/// Resolved backend for a Native Lock transaction. Distinct from
/// `NativeLockTransactionBackend` so that nil journals can be represented
/// explicitly rather than silently defaulting to the legacy path.
private enum NativeLockRuntimeBackend: Equatable {
    case legacySystemCatalog
    case userAerials
    /// Old journal with no backend field on an OS where the legacy path is
    /// not safe to assume (macOS 26).
    case unknownLegacy

    var logDescription: String {
        switch self {
        case .legacySystemCatalog: "legacySystemCatalog"
        case .userAerials: "userAerials"
        case .unknownLegacy: "unknownLegacy"
        }
    }
}

@MainActor
final class NativeLockController {
    private let container: SharedContainer
    private let store: NativeLockUserTransactionStore

    init(container: SharedContainer) {
        self.container = container
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: container.rootURL.path
        )
        let wallpaperIndexURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/com.apple.wallpaper/Store",
                isDirectory: true
            )
            .appendingPathComponent("Index.plist")
        self.store = NativeLockUserTransactionStore(
            supportRootURL: container.rootURL,
            wallpaperIndexURL: wallpaperIndexURL,
            userID: UInt32(getuid())
        )
    }

    func currentRecord() -> NativeLockTransactionRecord? {
        try? store.activeOrPendingTransaction()
    }

    /// Clears only the known macOS 26 legacy-helper preflight failure. The
    /// helper rejected that route before any system or user wallpaper write,
    /// so marking this journal restored does not perform a restore operation
    /// or discard a real Native Lock transaction.
    func discardKnownNoopLegacyPreflight() throws {
        guard let record = try store.activeOrPendingTransaction(),
              NativeLockRecovery.canDiscardKnownNoopLegacyPreflight(
                record.journal,
                operatingSystemMajorVersion: ProcessInfo.processInfo
                    .operatingSystemVersion.majorVersion
              ) else {
            throw NativeLockTransactionError.transactionMismatch
        }
        try store.markRestored(transactionID: record.request.transactionID)
        nativeLockLogger.notice(
            "Discarded known no-op legacy preflight transaction \(record.request.transactionID.uuidString, privacy: .public)"
        )
    }

    /// Performs user-level maintenance only. It never invokes the privileged
    /// helper or rewrites the system manifest/media. A drifted user wallpaper
    /// mapping is reconciled transactionally; an explicit renderer refresh is
    /// used at launch and after unlock so a failed WallpaperVideoExtension
    /// reader cannot poison the next Lock Screen session.
    func maintainActiveTransaction(
        refreshRenderer: Bool
    ) async throws -> NativeLockTransactionRecord? {
        guard let current = try store.activeOrPendingTransaction(),
              current.journal.phase == .active else {
            return currentRecord()
        }

        var record = current
        var restartedAgent = false
        let usesModernAerials = current.journal.backend == .userAerials
        if usesModernAerials {
            stopCompetingWallpaperRenderer()
        }
        let mappingMatches = try usesModernAerials
            ? store.linkedWallpaperMappingMatches(
                transactionID: current.request.transactionID
            )
            : store.wallpaperMappingMatches(
                transactionID: current.request.transactionID
            )
        if !mappingMatches {
            record = try withWallpaperAgentSuspended {
                try usesModernAerials
                    ? store.reconcileLinkedWallpaperMapping(
                        transactionID: current.request.transactionID
                    )
                    : store.reconcileWallpaperMapping(
                        transactionID: current.request.transactionID
                    )
            }
            restartedAgent = true
            try await verifyWallpaperMapping(
                transactionID: current.request.transactionID,
                modernAerials: usesModernAerials
            )
            nativeLockLogger.notice(
                "Reconciled active wallpaper choices for \(current.request.transactionID.uuidString, privacy: .public)"
            )
        }

        // Both supported backends use WallpaperAgent to host the Lock Screen
        // video extension. After launch or unlock, restart it once so a stale
        // reader cannot carry a black presentation surface into the next lock.
        if refreshRenderer, !restartedAgent {
            try refreshWallpaperRenderer()
            nativeLockLogger.notice(
                "Refreshed the native wallpaper renderer for \(current.request.transactionID.uuidString, privacy: .public)"
            )
        }
        return record
    }

    func apply(content: LiveContent) async throws -> NativeLockTransactionRecord {
        let usesModernAerials = ProcessInfo.processInfo
            .operatingSystemVersion.majorVersion == 26
        let modernManager = usesModernAerials
            ? NativeLockModernTransactionManager(environment: .live)
            : nil
        let linkedInitialization: (assetID: String, topology: NativeLockLinkedWallpaperTopology)?
        if let modernManager,
           try !store.hasLinkedWallpaperChoices() {
            linkedInitialization = (
                try modernManager.firstUsableAppleAerialAssetID(),
                try currentLinkedWallpaperTopology()
            )
        } else {
            linkedInitialization = nil
        }
        let sourceURL = container.mediaURL(for: content)
        let workURL = container.rootURL.appendingPathComponent(
            ".NativeLockPreparation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: workURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: workURL) }
        let mediaURL = workURL.appendingPathComponent("media.mov")
        let previewURL = workURL.appendingPathComponent(
            usesModernAerials ? "preview.png" : "preview.jpg"
        )
        try await prepareMedia(
            from: sourceURL,
            to: mediaURL,
            aerialCompatible: usesModernAerials
        )
        try await generatePreview(from: mediaURL, to: previewURL)

        let prepared = try store.prepare(
            sourceContentID: content.id,
            title: content.title,
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL
        )
        nativeLockLogger.notice(
            "Prepared transaction \(prepared.request.transactionID.uuidString, privacy: .public)"
        )
        do {
            if usesModernAerials {
                // Backdrop keeps a separate wallpaper renderer alive and can
                // immediately write its previous Aerial choice back over the
                // user store. Stop that renderer before Hikari's atomic
                // manifest/index update; its catalog records remain intact.
                stopCompetingWallpaperRenderer()
                let active = try withWallpaperAgentSuspended {
                    if let linkedInitialization {
                        _ = try store.materializeLinkedWallpaperTopology(
                            transactionID: prepared.request.transactionID,
                            assetID: linkedInitialization.assetID,
                            topology: linkedInitialization.topology
                        )
                    }
                    guard let modernManager else {
                        throw NativeLockTransactionError.invalidWallpaperStore
                    }
                    let result = try modernManager.apply(
                        request: prepared.request,
                        sourceTransactionURL: store.transactionDirectoryURL(
                            for: prepared.request.transactionID
                        )
                    )
                    _ = try store.markSystemApplied(
                        transactionID: prepared.request.transactionID,
                        manifestSHA256: result.manifestSHA256,
                        backend: .userAerials,
                        originalModernManifestSHA256: result.originalManifestSHA256
                    )
                    return try store.applyLinkedWallpaperMapping(
                        transactionID: prepared.request.transactionID
                    )
                }
                try await verifyWallpaperMapping(
                    transactionID: prepared.request.transactionID,
                    modernAerials: true
                )
                nativeLockLogger.notice(
                    "Activated macOS 26 user Aerial transaction \(prepared.request.transactionID.uuidString, privacy: .public)"
                )
                return active
            }
            let result = try runPrivilegedTool(
                operation: "apply",
                transactionID: prepared.request.transactionID,
                assetID: prepared.request.assetID
            )
            _ = try store.markSystemApplied(
                transactionID: prepared.request.transactionID,
                manifestSHA256: result.manifestSHA256
            )
            try await waitForSystemAssetIndexing(
                assetID: prepared.request.assetID
            )
            nativeLockLogger.notice(
                "System indexed asset \(prepared.request.assetID.uuidString, privacy: .public)"
            )
            let active = try withWallpaperAgentSuspended {
                try store.applyWallpaperMapping(
                    transactionID: prepared.request.transactionID
                )
            }
            try await verifyWallpaperMapping(
                transactionID: prepared.request.transactionID,
                modernAerials: false
            )
            nativeLockLogger.notice(
                "Activated transaction \(prepared.request.transactionID.uuidString, privacy: .public)"
            )
            return active
        } catch {
            nativeLockLogger.error(
                "Apply failed for \(prepared.request.transactionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            try? store.markRecoveryRequired(
                transactionID: prepared.request.transactionID,
                error: error.localizedDescription
            )
            throw error
        }
    }

    func restore() throws {
        guard let record = try store.activeOrPendingTransaction() else {
            throw NativeLockTransactionError.transactionNotFound
        }
        _ = try store.beginRestore(transactionID: record.request.transactionID)
        do {
            // Restore the user mapping first. If the helper is unavailable,
            // the Lock Screen no longer points at the custom asset even though
            // root cleanup may still require repair.
            try withWallpaperAgentSuspended {
                try store.restoreWallpaperMapping(
                    transactionID: record.request.transactionID
                )
            }
            // Resolve the backend explicitly. A nil backend in an old journal
            // must never silently fall through to the privileged helper on
            // macOS 26 — that would write to the legacy root-owned catalog.
            let currentMajorVersion = ProcessInfo.processInfo
                .operatingSystemVersion.majorVersion
            let resolvedBackend = resolveBackend(
                journalBackend: record.journal.backend,
                currentMajorVersion: currentMajorVersion
            )
            nativeLockLogger.notice(
                "Restore backend=\(resolvedBackend.logDescription, privacy: .public) macOS=\(currentMajorVersion, privacy: .public) transactionID=\(record.request.transactionID.uuidString, privacy: .public) journalBackend=\(record.journal.backend?.rawValue ?? "nil", privacy: .public)"
            )
            switch resolvedBackend {
            case .userAerials:
                if let originalManifestSHA256 = record.journal.originalModernManifestSHA256 {
                    try NativeLockModernTransactionManager(environment: .live).restore(
                        request: record.request,
                        sourceTransactionURL: store.transactionDirectoryURL(
                            for: record.request.transactionID
                        ),
                        originalManifestSHA256: originalManifestSHA256,
                        appliedManifestSHA256: record.journal.systemManifestAppliedSHA256
                    )
                }
            case .legacySystemCatalog:
                _ = try runPrivilegedTool(
                    operation: "restore",
                    transactionID: record.request.transactionID,
                    assetID: record.request.assetID
                )
            case .unknownLegacy:
                // The journal predates the backend field and we are on macOS 26.
                // We cannot safely invoke the legacy helper or the modern
                // manager. Return a recovery-oriented error.
                nativeLockLogger.error(
                    "Restore refused: old journal with nil backend on macOS \(currentMajorVersion, privacy: .public) for \(record.request.transactionID.uuidString, privacy: .public)"
                )
                throw NativeLockTransactionError
                    .legacyTransactionUnsupportedOnCurrentOperatingSystem(currentMajorVersion)
            }
            try store.markRestored(transactionID: record.request.transactionID)
            nativeLockLogger.notice(
                "Restored transaction \(record.request.transactionID.uuidString, privacy: .public)"
            )
        } catch {
            nativeLockLogger.error(
                "Restore failed for \(record.request.transactionID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            try? store.markRecoveryRequired(
                transactionID: record.request.transactionID,
                error: error.localizedDescription
            )
            throw error
        }
    }

    private func prepareMedia(
        from sourceURL: URL,
        to destinationURL: URL,
        aerialCompatible: Bool
    ) async throws {
        if aerialCompatible {
            try await Task.detached(priority: .utility) {
                try Self.transcodeForAerial(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL
                )
            }.value
            return
        }
        let asset = AVURLAsset(url: sourceURL)
        guard try await asset.load(.isPlayable),
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty else {
            throw LuminaError.unreadableVideo
        }
        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw LuminaError.unreadableVideo
        }
        // The Lock Screen extension opens this movie cold. Keep the movie
        // header before its media payload so it can discover the first frame
        // without scanning a high-bitrate 4K file from the end.
        export.shouldOptimizeForNetworkUse = true
        try await export.export(to: destinationURL, as: .mov)
    }

    /// macOS 26's Aerial renderer expects the same shape as Apple's local
    /// assets: video-only 10-bit HEVC (Main10), frequent keyframes and no
    /// frame reordering. A passthrough H.264/8-bit movie can be accepted by
    /// the manifest but is later discarded by WallpaperAgent, which leaves
    /// the Linked choice pointing at the previous asset.
    private nonisolated static func transcodeForAerial(
        sourceURL: URL,
        destinationURL: URL
    ) throws {
        try? FileManager.default.removeItem(at: destinationURL)
        let asset = AVURLAsset(url: sourceURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw LuminaError.unreadableVideo
        }

        let transform = track.preferredTransform
        let displayedBounds = CGRect(
            origin: .zero,
            size: track.naturalSize
        )
        .applying(transform)
        .standardized
        let sourceWidth = displayedBounds.width
        let sourceHeight = displayedBounds.height
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw LuminaError.unreadableVideo
        }
        // Aerial's native video renderer expects a landscape canvas. Passing
        // a portrait movie through unchanged makes some macOS 26 builds
        // stretch the source to the display instead of preserving its aspect
        // ratio. Render every custom asset into the same 16:9 canvas as
        // Apple's Aerial movies and fit the source inside that canvas. This
        // intentionally adds letterbox bars rather than cropping or scaling
        // the source non-uniformly.
        let outputWidth = 1920
        let outputHeight = 1080
        let sourceScale = min(
            Double(outputWidth) / sourceWidth,
            Double(outputHeight) / sourceHeight
        )
        let fittedWidth = sourceWidth * sourceScale
        let fittedHeight = sourceHeight * sourceScale
        let offsetX = (Double(outputWidth) - fittedWidth) / 2.0
        let offsetY = (Double(outputHeight) - fittedHeight) / 2.0
        let frameRate = track.nominalFrameRate > 0
            ? max(1, Int(track.nominalFrameRate.rounded()))
            : 30

        // Give the compositor a neutral composition track.  Passing the
        // original AVAssetTrack directly makes AVAssetReaderVideoComposition-
        // Output apply the track's source-space origin while it evaluates
        // layer transforms.  That origin is harmless for landscape clips but
        // shifts a fitted portrait clip away from the canvas center.  A
        // composition track with an identity preferred transform makes the
        // transform below the sole owner of orientation, scale, and position.
        let sourceComposition = AVMutableComposition()
        guard let sourceTrack = sourceComposition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw LuminaError.unreadableVideo
        }
        try sourceTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.duration),
            of: track,
            at: .zero
        )
        sourceTrack.preferredTransform = .identity

        let reader = try AVAssetReader(asset: sourceComposition)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(
            width: outputWidth,
            height: outputHeight
        )
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(frameRate)
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: sourceComposition.duration
        )
        instruction.backgroundColor = CGColor(gray: 0, alpha: 1)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: sourceTrack
        )
        // Build the affine matrix explicitly. Using chained
        // `concatenating` calls here scales the centering translation on some
        // Core Graphics versions, which would introduce a second geometry
        // error for rotated source movies.
        let scale = CGFloat(sourceScale)
        let fitTransform = CGAffineTransform(
            a: transform.a * scale,
            b: transform.b * scale,
            c: transform.c * scale,
            d: transform.d * scale,
            tx: (transform.tx - displayedBounds.minX) * scale
                + CGFloat(offsetX),
            ty: (transform.ty - displayedBounds.minY) * scale
                + CGFloat(offsetY)
        )
        layerInstruction.setTransform(fitTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [sourceTrack],
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            ]
        )
        readerOutput.alwaysCopiesSampleData = false
        readerOutput.videoComposition = videoComposition
        guard reader.canAdd(readerOutput) else {
            throw LuminaError.unreadableVideo
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: 12_000_000,
            AVVideoMaxKeyFrameIntervalKey: frameRate,
            AVVideoMaxKeyFrameIntervalDurationKey: 1.0,
            AVVideoAllowFrameReorderingKey: false,
            AVVideoProfileLevelKey: kVTProfileLevel_HEVC_Main10_AutoLevel as String
        ]
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: outputWidth,
                AVVideoHeightKey: outputHeight,
                AVVideoCompressionPropertiesKey: compression
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw LuminaError.unreadableVideo
        }
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw LuminaError.unreadableVideo
        }
        writer.startSession(atSourceTime: .zero)

        let finished = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.hodadako.Hikari.native-lock-transcode")
        writerInput.requestMediaDataWhenReady(on: queue) {
            while writerInput.isReadyForMoreMediaData {
                if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                    guard writerInput.append(sampleBuffer) else {
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        finished.signal()
                        return
                    }
                } else {
                    writerInput.markAsFinished()
                    writer.finishWriting {
                        finished.signal()
                    }
                    return
                }
            }
        }
        finished.wait()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw LuminaError.unreadableVideo
        }
    }

    private func generatePreview(from mediaURL: URL, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let image: CGImage
        if #available(macOS 15.0, *) {
            image = try await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            ).image
        } else {
            image = try generator.copyCGImage(
                at: CMTime(seconds: 0.1, preferredTimescale: 600),
                actualTime: nil
            )
        }
        let isPNG = destinationURL.pathExtension.lowercased() == "png"
        let imageType = isPNG ? UTType.png.identifier : UTType.jpeg.identifier
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            imageType as CFString,
            1,
            nil
        ) else {
            throw LuminaError.unreadableVideo
        }
        CGImageDestinationAddImage(
            destination,
            image,
            isPNG ? nil : [
                kCGImageDestinationLossyCompressionQuality: 0.9
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw LuminaError.unreadableVideo
        }
    }

    private func currentLinkedWallpaperTopology() throws -> NativeLockLinkedWallpaperTopology {
        let spacesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")
        let spacesData = try Data(contentsOf: spacesURL)
        let spacesRoot = try PropertyListSerialization.propertyList(
            from: spacesData,
            options: [],
            format: nil
        )
        let spaceIDs = Self.spaceIDs(from: spacesRoot)
        let displayIDs = NSScreen.screens.compactMap { screen -> String? in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(
                      CGDirectDisplayID(number.uint32Value)
                  )?.takeRetainedValue() else {
                return nil
            }
            return (CFUUIDCreateString(nil, uuid) as String).uppercased()
        }
        let uniqueSpaceIDs = Array(NSOrderedSet(array: spaceIDs)) as? [String] ?? spaceIDs
        let uniqueDisplayIDs = Array(NSOrderedSet(array: displayIDs)) as? [String] ?? displayIDs
        guard !uniqueSpaceIDs.isEmpty, !uniqueDisplayIDs.isEmpty else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        return NativeLockLinkedWallpaperTopology(
            spaceIDs: uniqueSpaceIDs,
            displayIDs: uniqueDisplayIDs
        )
    }

    private static func spaceIDs(from value: Any) -> [String] {
        guard let root = value as? [String: Any],
              let configuration = root["SpacesDisplayConfiguration"] as? [String: Any],
              let management = configuration["Management Data"] as? [String: Any],
              let monitors = management["Monitors"] as? [[String: Any]] else {
            return []
        }
        return monitors
            .flatMap { $0["Spaces"] as? [[String: Any]] ?? [] }
            .compactMap { $0["uuid"] as? String }
    }

    /// Resolves the effective backend for a transaction, handling old journals
    /// where `backend` is nil. On macOS 26, nil must never map to the legacy
    /// system catalog — it is treated as an unidentifiable old transaction.
    private func resolveBackend(
        journalBackend: NativeLockTransactionBackend?,
        currentMajorVersion: Int
    ) -> NativeLockRuntimeBackend {
        switch journalBackend {
        case .userAerials:
            return .userAerials
        case .systemCatalog:
            return .legacySystemCatalog
        case nil:
            // Old journal with no backend field. On macOS 26 we cannot safely
            // assume this is a legacy catalog transaction — refuse it.
            if currentMajorVersion == 26 {
                return .unknownLegacy
            }
            // On macOS 15 a nil backend is a pre-split legacy transaction.
            return .legacySystemCatalog
        }
    }

    private func runPrivilegedTool(
        operation: String,
        transactionID: UUID,
        assetID: UUID
    ) throws -> NativeLockSystemResult {
        // Defensive guard: the privileged helper must never be invoked on
        // macOS 26. If routing logic fails elsewhere this is the last line
        // of defence before launching the legacy root-owned catalog tool.
        let currentMajorVersion = ProcessInfo.processInfo
            .operatingSystemVersion.majorVersion
        guard currentMajorVersion != 26 else {
            nativeLockLogger.error(
                "runPrivilegedTool called on macOS 26 — routing error, refusing to invoke helper"
            )
            throw NativeLockTransactionError.unsupportedOperatingSystem(currentMajorVersion)
        }
        guard let helperURL = Bundle.main.url(
            forAuxiliaryExecutable: "lumina-native-tool"
        ) else {
            throw NativeLockTransactionError.helperMissing
        }
        guard !helperURL.path.contains("\n"),
              !helperURL.path.contains("\r") else {
            throw NativeLockTransactionError.helperMissing
        }
        let command = [
            helperURL.path,
            operation,
            "--uid",
            String(getuid()),
            "--transaction",
            transactionID.uuidString
        ].map(shellQuoted).joined(separator: " ")
        let script = "do shell script " + appleScriptQuoted(command)
            + " with administrator privileges"
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script),
              let scriptResult = appleScript.executeAndReturnError(&error)
                .stringValue else {
            let message = (error?[NSAppleScript.errorMessage] as? String)
                ?? "Administrator authorization was cancelled or failed."
            throw NativeLockTransactionError.helperFailed(message)
        }
        guard let data = scriptResult.data(using: .utf8) else {
            throw NativeLockTransactionError.helperFailed("Invalid helper response.")
        }
        let result = try JSONDecoder().decode(NativeLockSystemResult.self, from: data)
        guard result.transactionID == transactionID,
              result.assetID == assetID,
              result.operation == operation || result.operation == "\(operation)-noop" else {
            throw NativeLockTransactionError.transactionMismatch
        }
        return result
    }

    private func withWallpaperAgentSuspended<Result>(
        _ operation: () throws -> Result
    ) throws -> Result {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.wallpaper.agent"
        )
        var stoppedProcessIDs: [pid_t] = []
        defer {
            for processID in stoppedProcessIDs {
                if kill(processID, SIGKILL) != 0, errno != ESRCH {
                    _ = kill(processID, SIGCONT)
                }
            }
            // WallpaperAerialsExtension is an XPC extension and is not
            // reliably returned by NSRunningApplication. Kill the exact
            // process name after the shared files are complete so its cached
            // manifest cannot rewrite the newly selected asset.
            signalNamedWallpaperProcess("WallpaperAerialsExtension", "KILL")
        }
        for application in applications {
            let processID = application.processIdentifier
            guard kill(processID, SIGSTOP) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
            stoppedProcessIDs.append(processID)
        }
        signalNamedWallpaperProcess("WallpaperAerialsExtension", "STOP")
        usleep(100_000)
        return try operation()
    }

    private func refreshWallpaperRenderer() throws {
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.wallpaper.agent"
        )
        for application in applications {
            let processID = application.processIdentifier
            if kill(processID, SIGTERM) != 0, errno != ESRCH {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
        }
        signalNamedWallpaperProcess("WallpaperAerialsExtension", "TERM")
    }

    @discardableResult
    private func signalNamedWallpaperProcess(
        _ processName: String,
        _ signalName: String
    ) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["-\(signalName)", processName]
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    /// Backdrop's helper is a second writer for the same user wallpaper
    /// index. It is safe to stop only the renderer process here: Backdrop's
    /// manifest/media records are external and remain untouched, while
    /// Hikari's transaction gains ownership of the active Linked choice.
    private func stopCompetingWallpaperRenderer() {
        if signalNamedWallpaperProcess("BackdropWallpaper", "TERM") {
            nativeLockLogger.notice(
                "Stopped the competing Backdrop wallpaper renderer before applying Native Lock"
            )
        }
    }

    private func verifyWallpaperMapping(
        transactionID: UUID,
        modernAerials: Bool
    ) async throws {
        for _ in 0..<200 {
            let matches = try modernAerials
                ? store.linkedWallpaperMappingMatches(transactionID: transactionID)
                : store.wallpaperMappingMatches(transactionID: transactionID)
            if matches {
                // A first successful read only proves the atomic write landed.
                // Keep sampling while WallpaperAgent and idleassetsd settle so
                // their delayed normalization cannot turn into a false success.
                try await Task.sleep(for: .milliseconds(150))
                continue
            }
            throw NativeLockTransactionError.wallpaperMappingRejected
        }
    }

    private func waitForSystemAssetIndexing(assetID: UUID) async throws {
        let databaseURLs = [
            NativeLockPaths.idleAssetsRoot.appendingPathComponent("Aerial.sqlite"),
            NativeLockPaths.idleAssetsRoot.appendingPathComponent("Aerial.sqlite-wal")
        ]
        let needle = Data(assetID.uuidString.utf8)
        for _ in 0..<200 {
            if databaseURLs.contains(where: { databaseURL in
                guard let data = try? Data(contentsOf: databaseURL) else {
                    return false
                }
                return data.range(of: needle) != nil
            }) {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NativeLockTransactionError.wallpaperMappingRejected
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
#endif
