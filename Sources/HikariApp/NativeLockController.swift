import AppKit
import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import HikariCore
import HikariNativeLock
import OSLog
import UniformTypeIdentifiers
import VideoToolbox

private let nativeLockLogger = Logger(
    subsystem: "com.hodadako.Hikari",
    category: "NativeLock"
)

@MainActor
final class NativeLockController {
    private static let aerialPreparationVersion = "aerial-hevc-main10-1920x1080-v1"

    private struct PreparedAerialMedia {
        let mediaURL: URL
        let previewURL: URL
    }

    private let container: SharedContainer
    private let store: NativeLockUserTransactionStore
    private(set) var transactionReadError: String?

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

    /// Reads the saved transaction and replaces any previous read error with this
    /// attempt's result. Unsupported runtimes preserve stale markers and staging.
    /// On macOS 26, the known unapplied legacy cleanup policy still applies.
    func currentRecord() -> NativeLockTransactionRecord? {
        let policy = NativeLockOperatingSystemPolicy.current
        let savedRecord: NativeLockTransactionRecord?
        do {
            savedRecord = try store.activeOrPendingTransaction(
                removeStaleMarker: policy.majorVersion == 15 || policy.majorVersion == 26
            )
            transactionReadError = nil
        } catch {
            transactionReadError = String(
                format: NSLocalizedString(
                    "Hikari could not read the saved Lock Screen transaction: %@",
                    comment: "Unreadable Native Lock transaction"
                ),
                error.localizedDescription
            )
            return nil
        }
        guard let record = savedRecord else { return nil }
        guard NativeLockRecovery.canDiscardUnappliedLegacyTransaction(
            record.journal,
            operatingSystemMajorVersion: policy.majorVersion
        ) else {
            return record
        }
        do {
            try store.discardUnappliedTransaction(
                transactionID: record.request.transactionID
            )
            nativeLockLogger.notice(
                "Discarded unapplied legacy transaction \(record.request.transactionID.uuidString, privacy: .public) on macOS 26"
            )
            return nil
        } catch {
            return record
        }
    }

    /// Builds the macOS 26 Aerial input ahead of a selection.  This never
    /// changes the wallpaper store; it only creates an atomically-published
    /// cache in Hikari's private support directory.
    func prepareMediaForNativeLock(content: LiveContent) async throws {
        guard NativeLockOperatingSystemPolicy.current.writeBackend?.isUserAerials == true,
              cachedPreparationURLs(for: content) == nil else {
            return
        }

        let cacheURL = container.nativeLockPreparationDirectoryURL(for: content)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: container.nativeLockPreparationDirectoryURL.path
        )
        // A ready cache is directory-atomic. Any existing directory that did
        // not pass `cachedPreparationURLs` is therefore stale or interrupted
        // preparation output and is safe to replace before retrying.
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            try FileManager.default.removeItem(at: cacheURL)
        }
        let temporaryURL = container.nativeLockPreparationDirectoryURL
            .appendingPathComponent(
                ".\(content.id.uuidString).preparing-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: temporaryURL,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let mediaURL = temporaryURL.appendingPathComponent("media.mov")
            let previewURL = temporaryURL.appendingPathComponent("preview.png")
            try await prepareMedia(
                from: container.mediaURL(for: content),
                to: mediaURL,
                aerialCompatible: true
            )
            try await generatePreview(from: mediaURL, to: previewURL)
            guard let versionData = Self.aerialPreparationVersion.data(
                using: .utf8
            ) else {
                throw HikariError.unreadableVideo
            }
            try versionData.write(
                to: temporaryURL.appendingPathComponent("version"),
                options: .atomic
            )
            // Do not overwrite a cache that another preparation task has
            // already completed. Both candidates are derived from the same
            // immutable managed media file.
            if !FileManager.default.fileExists(atPath: cacheURL.path) {
                try FileManager.default.moveItem(at: temporaryURL, to: cacheURL)
            }
            try? FileManager.default.removeItem(at: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    func hasPreparedMediaForNativeLock(content: LiveContent) -> Bool {
        cachedPreparationURLs(for: content) != nil
    }

    private func cachedPreparationURLs(
        for content: LiveContent
    ) -> PreparedAerialMedia? {
        let directoryURL = container.nativeLockPreparationDirectoryURL(for: content)
        let versionURL = directoryURL.appendingPathComponent("version")
        guard let versionData = try? Data(contentsOf: versionURL),
              String(data: versionData, encoding: .utf8)
                == Self.aerialPreparationVersion else {
            return nil
        }
        let mediaURL = directoryURL.appendingPathComponent("media.mov")
        let previewURL = directoryURL.appendingPathComponent("preview.png")
        guard FileManager.default.isReadableFile(atPath: mediaURL.path),
              FileManager.default.isReadableFile(atPath: previewURL.path) else {
            return nil
        }
        return PreparedAerialMedia(mediaURL: mediaURL, previewURL: previewURL)
    }

    /// Clears only the known macOS 26 legacy-helper preflight failure. The
    /// helper rejected that route before any system or user wallpaper write,
    /// so marking this journal restored does not perform a restore operation
    /// or discard a real Native Lock transaction.
    func discardKnownNoopLegacyPreflight() throws {
        let policy = NativeLockOperatingSystemPolicy.current
        guard policy.writeBackend?.isUserAerials == true,
              let record = try store.activeOrPendingTransaction(),
              NativeLockRecovery.canDiscardKnownNoopLegacyPreflight(
                record.journal,
                operatingSystemMajorVersion: policy.majorVersion
              ) else {
            throw NativeLockTransactionError.transactionMismatch
        }
        try store.discardUnappliedTransaction(
            transactionID: record.request.transactionID
        )
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
        let policy = NativeLockOperatingSystemPolicy.current
        guard policy.writeBackend != nil,
              let current = try store.activeOrPendingTransaction(),
              current.journal.phase == .active,
              policy.canModifyTransaction(
                backend: current.journal.backend,
                operatingSystemMajorVersion: current.journal.operatingSystemMajorVersion
              ) else {
            return currentRecord()
        }

        if current.journal.backend == .userAerials27 {
            do {
                let activation = NativeLockGoldenGateActivation.live
                guard activation.selectionMatches(request: current.request) else {
                    throw NativeLockTransactionError.transactionMismatch
                }
                _ = try NativeLockModernTransactionManager(environment: activation.environment(for: current.request))
                    .inspectStore(requiredAssetID: current.request.assetID.uuidString)
            } catch {
                try store.markRecoveryRequired(transactionID: current.request.transactionID, error: error.localizedDescription)
                throw error
            }
        }
        var record = current
        var restartedAgent = false
        let usesModernAerials = current.journal.backend?.isUserAerials == true
        let mappingMatches = try usesModernAerials
            ? store.linkedWallpaperMappingMatches(
                transactionID: current.request.transactionID
            )
            : store.wallpaperMappingMatches(
                transactionID: current.request.transactionID
            )
        if !mappingMatches {
            // Backdrop only needs to be stopped immediately before this
            // transaction writes the shared index. Avoid launching killall on
            // every healthy five-second maintenance pass.
            if usesModernAerials {
                stopCompetingWallpaperRenderer()
            }
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

    /// Applies a video through the reviewed runtime backend after store preflight.
    /// A failed transaction retains its recovery journal and verified backups.
    func apply(content: LiveContent) async throws -> NativeLockTransactionRecord {
        let policy = NativeLockOperatingSystemPolicy.current
        guard let backend = policy.writeBackend else {
            throw NativeLockTransactionError.unsupportedOperatingSystem(policy.majorVersion)
        }
        let usesModernAerials = backend.isUserAerials
        if backend == .userAerials { try validateAerialManifest() }
        if let current = try store.activeOrPendingTransaction() {
            guard usesModernAerials,
                  current.journal.phase == .active,
                  policy.canModifyTransaction(
                    backend: current.journal.backend,
                    operatingSystemMajorVersion: current.journal.operatingSystemMajorVersion
                  ) else {
                throw NativeLockTransactionError.activeTransactionExists
            }
            if current.request.sourceContentID == content.id {
                return current
            }
            try restore()
        }
        if backend == .userAerials27 { try NativeLockGoldenGateActivation.live.preflight() }
        var modernManager = usesModernAerials
            ? NativeLockModernTransactionManager(environment: .live)
            : nil
        let linkedInitialization: (assetID: String, topology: NativeLockLinkedWallpaperTopology)?
        if let modernManager,
           try !store.hasLinkedWallpaperChoices() {
            guard backend == .userAerials else { throw NativeLockTransactionError.noWallpaperChoices }
            linkedInitialization = (
                try modernManager.firstUsableAppleAerialAssetID(),
                try currentLinkedWallpaperTopology()
            )
        } else {
            linkedInitialization = nil
        }
        let preparedCache = usesModernAerials
            ? cachedPreparationURLs(for: content)
            : nil
        let workURL: URL?
        let mediaURL: URL
        let previewURL: URL
        if let preparedCache {
            workURL = nil
            mediaURL = preparedCache.mediaURL
            previewURL = preparedCache.previewURL
        } else {
            let newWorkURL = container.rootURL.appendingPathComponent(
                ".NativeLockPreparation-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: newWorkURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            workURL = newWorkURL
            mediaURL = newWorkURL.appendingPathComponent("media.mov")
            previewURL = newWorkURL.appendingPathComponent(
                usesModernAerials ? "preview.png" : "preview.jpg"
            )
            try await prepareMedia(
                from: container.mediaURL(for: content),
                to: mediaURL,
                aerialCompatible: usesModernAerials
            )
            try await generatePreview(from: mediaURL, to: previewURL)
        }
        defer {
            if let workURL {
                try? FileManager.default.removeItem(at: workURL)
            }
        }

        let prepared = try store.prepare(
            sourceContentID: content.id,
            title: content.title,
            preparedMediaURL: mediaURL,
            preparedPreviewURL: previewURL,
            operatingSystemMajorVersion: policy.majorVersion
        )
        nativeLockLogger.notice(
            "Prepared transaction \(prepared.request.transactionID.uuidString, privacy: .public)"
        )
        do {
            var activationHash: String?
            if backend == .userAerials27 {
                let activation = NativeLockGoldenGateActivation.live
                let hash = try activation.prepare(request: prepared.request,
                    transactionURL: store.transactionDirectoryURL(for: prepared.request.transactionID))
                try store.markAerialActivationPrepared(transactionID: prepared.request.transactionID, sha256: hash)
                activationHash = hash
                modernManager = NativeLockModernTransactionManager(environment: activation.environment(for: prepared.request))
            }
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
                        backend: backend,
                        originalModernManifestSHA256: result.originalManifestSHA256
                    )
                    if let activationHash {
                        try NativeLockGoldenGateActivation.live.activate(request: prepared.request,
                            transactionURL: store.transactionDirectoryURL(for: prepared.request.transactionID),
                            backupSHA256: activationHash)
                    }
                    return try store.applyLinkedWallpaperMapping(
                        transactionID: prepared.request.transactionID
                    )
                }
                try await verifyWallpaperMapping(
                    transactionID: prepared.request.transactionID,
                    modernAerials: true
                )
                nativeLockLogger.notice(
                    "Activated user Aerial transaction \(prepared.request.transactionID.uuidString, privacy: .public)"
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

    /// Restores a transaction only when its backend matches the runtime policy.
    /// Rejects unsupported recovery before journal changes or wallpaper process control.
    func restore() throws {
        let policy = NativeLockOperatingSystemPolicy.current
        guard let runtimeBackend = policy.writeBackend else {
            throw NativeLockTransactionError.transactionRestoreUnavailable(policy.majorVersion)
        }
        guard let record = try store.activeOrPendingTransaction(removeStaleMarker: false) else {
            throw NativeLockTransactionError.transactionNotFound
        }
        let upgradeRestore = policy.requiresUpgradeRestore(
            backend: record.journal.backend,
            operatingSystemMajorVersion: record.journal.operatingSystemMajorVersion
        )
        guard policy.canModifyTransaction(backend: record.journal.backend,
            operatingSystemMajorVersion: record.journal.operatingSystemMajorVersion) || upgradeRestore else {
            throw NativeLockTransactionError.transactionRestoreUnavailable(policy.majorVersion)
        }
        let transactionURL = store.transactionDirectoryURL(for: record.request.transactionID)
        let backend = record.journal.backend ?? runtimeBackend
        let activation = backend == .userAerials27 ? NativeLockGoldenGateActivation.live : nil
        var originalManifestHash = record.journal.originalModernManifestSHA256
        if let activation, let hash = record.journal.aerialActivationSHA256 {
            try activation.validateRestore(request: record.request, transactionURL: transactionURL, backupSHA256: hash)
            // A crash after catalog commit but before markSystemApplied still
            // has the prepared activation digest and the original manifest copy.
            if originalManifestHash == nil,
               FileManager.default.fileExists(atPath: transactionURL.appendingPathComponent(NativeLockPaths.originalModernManifestFilename).path) {
                originalManifestHash = try activation.originalCatalogSHA256(request: record.request,
                    transactionURL: transactionURL, backupSHA256: hash)
            }
        } else if backend == .userAerials27, record.journal.systemManifestAppliedSHA256 != nil {
            throw NativeLockTransactionError.invalidHash
        }
        let manager: NativeLockModernTransactionManager?
        if let activation {
            manager = NativeLockModernTransactionManager(environment: activation.environment(for: record.request))
        } else if backend == .userAerials {
            let legacy = NativeLockModernEnvironment.live
            manager = NativeLockModernTransactionManager(environment: NativeLockModernEnvironment(
                wallpaperRootURL: legacy.wallpaperRootURL, manifestURL: legacy.manifestURL,
                mediaDirectoryURL: legacy.mediaDirectoryURL, previewDirectoryURL: legacy.previewDirectoryURL,
                supportedOperatingSystemMajorVersions: upgradeRestore ? [27] : [26],
                operatingSystemMajorVersion: policy.majorVersion))
        } else { manager = nil }
        // Validate both rollback inputs before journal, agent, or shared writes.
        try store.validateWallpaperRestore(transactionID: record.request.transactionID, forceSelective: upgradeRestore)
        if let manager, let originalManifestHash {
            try manager.validateRestore(originalManifestSHA256: originalManifestHash, sourceTransactionURL: transactionURL)
        } else if upgradeRestore {
            throw NativeLockTransactionError.transactionRestoreUnavailable(policy.majorVersion)
        }
        _ = try store.beginRestore(transactionID: record.request.transactionID)
        do {
            try withWallpaperAgentSuspended {
                try store.restoreWallpaperMapping(transactionID: record.request.transactionID, forceSelective: upgradeRestore)
                if let manager, let originalManifestHash {
                    try manager.restore(request: record.request, sourceTransactionURL: transactionURL,
                        originalManifestSHA256: originalManifestHash,
                        appliedManifestSHA256: record.journal.systemManifestAppliedSHA256,
                        forceSelective: upgradeRestore)
                }
                if let activation, let hash = record.journal.aerialActivationSHA256 {
                    try activation.restore(request: record.request, transactionURL: transactionURL, backupSHA256: hash)
                }
            }
            if backend == .systemCatalog {
                _ = try runPrivilegedTool(operation: "restore", transactionID: record.request.transactionID,
                                          assetID: record.request.assetID)
            }
            try store.markRestored(transactionID: record.request.transactionID)
            nativeLockLogger.notice("Restored transaction \(record.request.transactionID.uuidString, privacy: .public)")
        } catch {
            try? store.markRecoveryRequired(transactionID: record.request.transactionID, error: error.localizedDescription)
            throw error
        }
    }

    private func prepareMedia(
        from sourceURL: URL,
        to destinationURL: URL,
        aerialCompatible: Bool
    ) async throws {
        if aerialCompatible {
            // AVAssetWriter selects VideoToolbox's hardware HEVC encoder when
            // available. User-initiated priority keeps a freshly imported
            // selection from being delayed behind maintenance work, without
            // adding unsupported renderer prewarming.
            try await Task.detached(priority: .userInitiated) {
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
            throw HikariError.unreadableVideo
        }
        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw HikariError.unreadableVideo
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
            throw HikariError.unreadableVideo
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
            throw HikariError.unreadableVideo
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
            throw HikariError.unreadableVideo
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
            throw HikariError.unreadableVideo
        }
        reader.add(readerOutput)

        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let encoderSpecification: [String: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder
                as String: true
        ]
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
                AVVideoEncoderSpecificationKey: encoderSpecification,
                AVVideoCompressionPropertiesKey: compression
            ]
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw HikariError.unreadableVideo
        }
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw HikariError.unreadableVideo
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
            throw HikariError.unreadableVideo
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
            throw HikariError.unreadableVideo
        }
        CGImageDestinationAddImage(
            destination,
            image,
            isPNG ? nil : [
                kCGImageDestinationLossyCompressionQuality: 0.9
            ] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw HikariError.unreadableVideo
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

    /// Checks the live user Aerial manifest before any shared-store or agent changes.
    /// Throws a prerequisite error for a missing or unrecognized manifest.
    private func validateAerialManifest() throws {
        switch NativeLockSafetyInspector.aerialManifestState(
            manifestURL: NativeLockModernEnvironment.live.manifestURL
        ) {
        case .ready: return
        case .missing: throw NativeLockTransactionError.aerialCatalogMissing
        case .invalid: throw NativeLockTransactionError.invalidWallpaperStore
        }
    }

    /// Runs the embedded one-shot helper after verifying the legacy runtime backend.
    /// Validates its transaction identifiers and operation before accepting the result.
    private func runPrivilegedTool(
        operation: String,
        transactionID: UUID,
        assetID: UUID
    ) throws -> NativeLockSystemResult {
        let policy = NativeLockOperatingSystemPolicy.current
        guard policy.writeBackend == .systemCatalog else {
            throw NativeLockTransactionError.unsupportedOperatingSystem(policy.majorVersion)
        }
        guard let helperURL = Bundle.main.url(
            forAuxiliaryExecutable: "hikari-native-tool"
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
                "Stopped the competing Backdrop wallpaper renderer before updating Native Lock mapping"
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
