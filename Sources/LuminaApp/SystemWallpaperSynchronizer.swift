import AppKit
import AVFoundation
import ImageIO
import LuminaCore
import UniformTypeIdentifiers

@MainActor
final class SystemWallpaperSynchronizer {
    private let container: SharedContainer
    private let fileManager: FileManager
    private var generationTask: Task<Void, Never>?
    private var appliedContentID: UUID?
    private var appliedScalingMode: ScalingMode?

    init(
        container: SharedContainer,
        fileManager: FileManager = .default
    ) {
        self.container = container
        self.fileManager = fileManager
    }

    func synchronize(
        content: LiveContent?,
        mediaURL: URL?,
        thumbnailURL: URL?,
        scalingMode: ScalingMode,
        force: Bool = false,
        onError: @escaping (Error) -> Void
    ) {
        guard let content, let mediaURL else { return }
        guard
            force
                || appliedContentID != content.id
                || appliedScalingMode != scalingMode
        else {
            return
        }

        generationTask?.cancel()
        appliedContentID = content.id
        appliedScalingMode = scalingMode

        let posterURL = posterURL(for: content)
        if fileManager.fileExists(atPath: posterURL.path) {
            apply(
                imageURL: posterURL,
                scalingMode: scalingMode,
                onError: onError
            )
            return
        }

        if let thumbnailURL,
           fileManager.fileExists(atPath: thumbnailURL.path) {
            apply(
                imageURL: thumbnailURL,
                scalingMode: scalingMode,
                onError: onError
            )
        }

        let requestedContentID = content.id
        let maximumSize = maximumPosterSize
        generationTask = Task { [weak self] in
            let generatedURL = try? await Self.generatePoster(
                mediaURL: mediaURL,
                destinationURL: posterURL,
                maximumSize: maximumSize
            )
            guard
                !Task.isCancelled,
                let self,
                self.appliedContentID == requestedContentID,
                let generatedURL
            else {
                return
            }
            self.apply(
                imageURL: generatedURL,
                scalingMode: scalingMode,
                onError: onError
            )
        }
    }

    func cancelPendingWork() {
        generationTask?.cancel()
        generationTask = nil
    }

    private var maximumPosterSize: CGSize {
        let screens = NSScreen.screens
        let width = screens.map { $0.frame.width * $0.backingScaleFactor }.max() ?? 2560
        let height = screens.map { $0.frame.height * $0.backingScaleFactor }.max() ?? 1440
        return CGSize(width: min(width, 4096), height: min(height, 4096))
    }

    private func posterURL(for content: LiveContent) -> URL {
        container.desktopPosterURL(for: content)
    }

    private func apply(
        imageURL: URL,
        scalingMode: ScalingMode,
        onError: (Error) -> Void
    ) {
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
                .allowClipping: scalingMode == .fill
            ]
            do {
                try workspace.setDesktopImageURL(
                    imageURL,
                    for: screen,
                    options: options
                )
            } catch {
                onError(error)
            }
        }
    }

    nonisolated private static func generatePoster(
        mediaURL: URL,
        destinationURL: URL,
        maximumSize: CGSize
    ) async throws -> URL {
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let asset = AVURLAsset(url: mediaURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        let image = try await generator.image(
            at: CMTime(seconds: 0.1, preferredTimescale: 600)
        ).image
        guard
            let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return destinationURL
    }
}
