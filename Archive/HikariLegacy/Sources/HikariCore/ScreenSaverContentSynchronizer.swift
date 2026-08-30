import Foundation

public actor ScreenSaverContentSynchronizer {
    private struct Signature: Equatable {
        let contentID: UUID?
        let fileSize: Int64?
        let scalingMode: ScalingMode
    }

    private let sourceContainer: SharedContainer
    private let destinationContainer: SharedContainer
    private let fileManager: FileManager
    private var lastSignature: Signature?

    public init(
        sourceContainer: SharedContainer,
        destinationContainer: SharedContainer
    ) {
        self.sourceContainer = sourceContainer
        self.destinationContainer = destinationContainer
        self.fileManager = FileManager()
    }

    public init(
        sourceContainer: SharedContainer,
        destinationContainer: SharedContainer,
        fileManager: FileManager
    ) {
        self.sourceContainer = sourceContainer
        self.destinationContainer = destinationContainer
        self.fileManager = fileManager
    }

    public func synchronize(
        content: LiveContent?,
        settings: HikariSettings,
        force: Bool = false
    ) throws {
        try Task.checkCancellation()
        let signature = Signature(
            contentID: content?.id,
            fileSize: content?.fileSize,
            scalingMode: settings.scalingMode
        )
        if !force,
           lastSignature == signature,
           destinationHasMedia(for: content) {
            return
        }

        if let content {
            try copyIfNeeded(
                from: sourceContainer.mediaURL(for: content),
                to: destinationContainer.mediaURL(for: content)
            )
            if let sourceThumbnailURL = sourceContainer.thumbnailURL(for: content),
               fileManager.fileExists(atPath: sourceThumbnailURL.path),
               let destinationThumbnailURL = destinationContainer.thumbnailURL(for: content) {
                try copyIfNeeded(
                    from: sourceThumbnailURL,
                    to: destinationThumbnailURL
                )
            }
        }

        try Task.checkCancellation()
        try ContentStore(container: destinationContainer).save(
            content.map { [$0] } ?? []
        )
        try SettingsStore(container: destinationContainer).save(settings)
        lastSignature = signature
    }

    private func destinationHasMedia(for content: LiveContent?) -> Bool {
        guard let content else { return true }
        return fileManager.fileExists(
            atPath: destinationContainer.mediaURL(for: content).path
        )
    }

    private func copyIfNeeded(from sourceURL: URL, to destinationURL: URL) throws {
        let sourceSize = try fileSize(at: sourceURL)
        if fileManager.fileExists(atPath: destinationURL.path),
           try fileSize(at: destinationURL) == sourceSize {
            return
        }

        try Task.checkCancellation()
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).syncing")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        try Task.checkCancellation()

        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw CocoaError(.fileReadUnknown)
        }
        return Int64(size)
    }
}
