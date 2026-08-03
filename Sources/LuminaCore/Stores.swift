import Foundation

public final class SettingsStore {
    public let container: SharedContainer
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(container: SharedContainer) {
        self.container = container
        self.encoder = JSONEncoder.luminaEncoder
        self.decoder = JSONDecoder.luminaDecoder
    }

    public func load() -> LuminaSettings {
        guard
            let data = try? Data(contentsOf: container.settingsURL),
            let settings = try? decoder.decode(LuminaSettings.self, from: data)
        else {
            return LuminaSettings()
        }
        return settings
    }

    public func save(_ settings: LuminaSettings) throws {
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
        self.encoder = JSONEncoder.luminaEncoder
        self.decoder = JSONDecoder.luminaDecoder
    }

    public func load() -> [LiveContent] {
        guard
            let data = try? Data(contentsOf: container.contentsURL),
            let contents = try? decoder.decode([LiveContent].self, from: data)
        else {
            return []
        }
        return contents
    }

    public func save(_ contents: [LiveContent]) throws {
        let data = try encoder.encode(contents)
        try data.write(to: container.contentsURL, options: .atomic)
    }

    public func delete(_ content: LiveContent, from contents: [LiveContent]) throws -> [LiveContent] {
        let updated = contents.filter { $0.id != content.id }
        let fileManager = FileManager.default
        let mediaURL = container.mediaURL(for: content)
        let thumbnailURL = container.thumbnailURL(for: content)

        if fileManager.fileExists(atPath: mediaURL.path) {
            try fileManager.removeItem(at: mediaURL)
        }
        if let thumbnailURL, fileManager.fileExists(atPath: thumbnailURL.path) {
            try fileManager.removeItem(at: thumbnailURL)
        }
        try save(updated)
        return updated
    }
}

private extension JSONEncoder {
    static var luminaEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var luminaDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
