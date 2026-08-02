import Foundation

public struct SharedContainer: Sendable {
    public static let applicationSupportDirectoryName = "Lumina"

    public let rootURL: URL

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

    public var desktopPostersDirectoryURL: URL {
        rootURL.appendingPathComponent("DesktopPosters", isDirectory: true)
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

    public func mediaURL(for content: LiveContent) -> URL {
        rootURL.appendingPathComponent(content.relativePath)
    }

    public func thumbnailURL(for content: LiveContent) -> URL? {
        content.thumbnailRelativePath.map { rootURL.appendingPathComponent($0) }
    }

    public func desktopPosterURL(for content: LiveContent) -> URL {
        desktopPostersDirectoryURL.appendingPathComponent("\(content.id.uuidString).jpg")
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
            at: desktopPostersDirectoryURL,
            withIntermediateDirectories: true
        )
    }
}
