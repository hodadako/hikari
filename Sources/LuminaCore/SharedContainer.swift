import Foundation

public struct SharedContainer: Sendable {
    public static let applicationSupportDirectoryName = "Lumina"

    public let rootURL: URL

    /// The legacy ScreenSaver host is sandboxed separately from Lumina.  Its
    /// support directory is the one location both the app and the `.saver`
    /// bundle can use for the synchronized video, settings, and metadata.
    ///
    /// Keep this explicit instead of asking each process for its default
    /// Application Support URL: that URL changes with the current process's
    /// sandbox and can otherwise make the saver load an empty library.
    public static var screenSaverRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support",
                isDirectory: true
            )
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
    }

    public init(rootURL: URL? = nil) throws {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.rootURL = support.appendingPathComponent(
                Self.applicationSupportDirectoryName,
                isDirectory: true
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
        // Legacy DesktopPosters files, if present, are deliberately left in
        // this Lumina-only support directory and are never used as the macOS
        // desktop wallpaper.
    }
}
