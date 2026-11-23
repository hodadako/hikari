import Foundation

public final class SettingsStore {
    public let container: SharedContainer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(container: SharedContainer) {
        self.container = container
        self.encoder = JSONEncoder.hikariEncoder
        self.decoder = JSONDecoder.hikariDecoder
    }

    public func load() -> HikariSettings {
        guard
            let data = try? Data(contentsOf: container.settingsURL),
            let settings = try? decoder.decode(HikariSettings.self, from: data)
        else {
            return HikariSettings()
        }
        return settings
    }

    public func save(_ settings: HikariSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: container.settingsURL, options: .atomic)
    }
}

public final class ContentStore {
    public let container: SharedContainer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(container: SharedContainer) {
        self.container = container
        self.encoder = JSONEncoder.hikariEncoder
        self.decoder = JSONDecoder.hikariDecoder
    }

    public func load() throws -> [LiveContent] {
        let data: Data
        do {
            data = try Data(contentsOf: container.contentsURL)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let contents = try decoder.decode([LiveContent].self, from: data)
        retryPendingDeletions(keeping: contents)
        return contents
    }

    public func save(_ contents: [LiveContent]) throws {
        let data = try encoder.encode(contents)
        try data.write(to: container.contentsURL, options: .atomic)
    }

    public func delete(_ content: LiveContent, from contents: [LiveContent]) throws -> [LiveContent] {
        guard let stored = contents.first(where: { $0.id == content.id }) else { return contents }
        let updated = contents.filter { $0.id != stored.id }
        try FileManager.default.createDirectory(at: pendingDeletions, withIntermediateDirectories: true)
        let marker = pendingDeletions.appendingPathComponent(stored.id.uuidString + ".json")
        try encoder.encode(stored).write(to: marker, options: .atomic)
        try save(updated)
        // Once the index commits, cleanup can finish on the next successful load.
        try? finishDeletion(stored, marker: marker, keeping: updated)
        return updated
    }

    private var pendingDeletions: URL {
        container.rootURL.appendingPathComponent("PendingDeletions", isDirectory: true)
    }

    private func retryPendingDeletions(keeping contents: [LiveContent]) {
        guard let markers = try? FileManager.default.contentsOfDirectory(
            at: pendingDeletions, includingPropertiesForKeys: nil
        ) else { return }
        for marker in markers where marker.pathExtension == "json" {
            guard let data = try? Data(contentsOf: marker),
                  let item = try? decoder.decode(LiveContent.self, from: data),
                  marker.deletingPathExtension().lastPathComponent == item.id.uuidString else { continue }
            try? finishDeletion(item, marker: marker, keeping: contents)
        }
    }

    private func finishDeletion(_ item: LiveContent, marker: URL, keeping contents: [LiveContent]) throws {
        // A still-listed ID means the index write failed or never happened.
        if !contents.contains(where: { $0.id == item.id }) {
            let media = container.mediaURL(for: item).standardizedFileURL
            if media.deletingLastPathComponent().path == container.mediaDirectoryURL.standardizedFileURL.path,
               !contents.contains(where: { container.mediaURL(for: $0).standardizedFileURL == media }) {
                try removeIfPresent(media)
            }
            if let thumbnail = container.thumbnailURL(for: item)?.standardizedFileURL,
               thumbnail.deletingLastPathComponent().path == container.thumbnailsDirectoryURL.standardizedFileURL.path,
               !contents.contains(where: { container.thumbnailURL(for: $0)?.standardizedFileURL == thumbnail }) {
                try removeIfPresent(thumbnail)
            }
            try removeIfPresent(container.nativeLockPreparationDirectoryURL(for: item))
        }
        try removeIfPresent(marker)
    }

    private func removeIfPresent(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }
}

private extension JSONEncoder {
    static var hikariEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var hikariDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
