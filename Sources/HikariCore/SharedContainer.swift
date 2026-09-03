import Foundation

public struct SharedContainer: Sendable {
    public static let applicationSupportDirectoryName = "Hikari"

    public static func applicationSupportRootURL(
        directoryName: String = Self.applicationSupportDirectoryName,
        fileManager: FileManager = .default
    ) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    public let rootURL: URL

    public init(
        rootURL: URL? = nil,
        applicationSupportDirectoryName: String = Self.applicationSupportDirectoryName
    ) throws {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            self.rootURL = try Self.applicationSupportRootURL(
                directoryName: applicationSupportDirectoryName
            )
        }
        try prepareDirectories()
    }

    public var mediaDirectoryURL: URL {
        rootURL.appendingPathComponent("Media", isDirectory: true)
    }

    public var thumbnailsDirectoryURL: URL {
        rootURL.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    /// Per-library, prepared Aerial inputs. These are deliberately separate
    /// from the original media: desktop wallpaper always keeps using the
    /// user's imported file at its original quality.
    public var nativeLockPreparationDirectoryURL: URL {
        rootURL.appendingPathComponent("NativeLockPreparation", isDirectory: true)
    }

    public func nativeLockPreparationDirectoryURL(
        for content: LiveContent
    ) -> URL {
        nativeLockPreparationDirectoryURL.appendingPathComponent(
            content.id.uuidString,
            isDirectory: true
        )
    }

    public var settingsURL: URL {
        rootURL.appendingPathComponent("settings.json")
    }

    public var contentsURL: URL {
        rootURL.appendingPathComponent("contents.json")
    }

    public var customAppIconURL: URL {
        rootURL.appendingPathComponent("CustomAppIcon.png")
    }

    public var customMenuBarIconURL: URL {
        rootURL.appendingPathComponent("CustomMenuBarIcon.png")
    }

    public func mediaURL(for content: LiveContent) -> URL {
        rootURL.appendingPathComponent(content.relativePath)
    }

    public func thumbnailURL(for content: LiveContent) -> URL? {
        content.thumbnailRelativePath.map { rootURL.appendingPathComponent($0) }
    }

    private func prepareDirectories() throws {
        try FileManager.default.createDirectory(
            at: mediaDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: thumbnailsDirectoryURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: nativeLockPreparationDirectoryURL,
            withIntermediateDirectories: true
        )
        // Legacy DesktopPosters files, if present, are deliberately left in
        // this Hikari-only support directory and are never used as the macOS
        // desktop wallpaper.
    }
}
