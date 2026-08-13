#if LUMINA_NATIVE_LOCAL
import AppKit
import AVFoundation
import Darwin
import Foundation
import ImageIO
import LuminaCore
import LuminaNativeLock
import OSLog
import UniformTypeIdentifiers

private let nativeLockLogger = Logger(
    subsystem: "com.hodadako.Lumina.NativeLocal",
    category: "NativeLock"
)

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

    func apply(content: LiveContent) async throws -> NativeLockTransactionRecord {
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
        let previewURL = workURL.appendingPathComponent("preview.jpg")
        try await prepareMedia(from: sourceURL, to: mediaURL)
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
                transactionID: prepared.request.transactionID
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
            _ = try runPrivilegedTool(
                operation: "restore",
                transactionID: record.request.transactionID,
                assetID: record.request.assetID
            )
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

    private func prepareMedia(from sourceURL: URL, to destinationURL: URL) async throws {
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
        export.shouldOptimizeForNetworkUse = false
        try await export.export(to: destinationURL, as: .mov)
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
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw LuminaError.unreadableVideo
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw LuminaError.unreadableVideo
        }
    }

    private func runPrivilegedTool(
        operation: String,
        transactionID: UUID,
        assetID: UUID
    ) throws -> NativeLockSystemResult {
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
        }
        for application in applications {
            let processID = application.processIdentifier
            guard kill(processID, SIGSTOP) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPERM)
            }
            stoppedProcessIDs.append(processID)
        }
        if !stoppedProcessIDs.isEmpty {
            usleep(100_000)
        }
        return try operation()
    }

    private func verifyWallpaperMapping(transactionID: UUID) async throws {
        for _ in 0..<200 {
            if try store.wallpaperMappingMatches(transactionID: transactionID) {
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
