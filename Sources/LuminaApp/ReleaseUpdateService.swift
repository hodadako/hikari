import Foundation
import LuminaCore

struct ReleaseAsset: Codable, Equatable, Sendable {
    let name: String
    let browserDownloadURL: URL
    let size: Int

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
    }
}

struct LatestRelease: Codable, Equatable, Sendable {
    let tagName: String
    let name: String
    let htmlURL: URL
    let assets: [ReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
    }

    var version: LuminaVersion? {
        LuminaVersion(tagName)
    }

    var displayVersion: String {
        version.map { "v\($0.description)" } ?? tagName
    }

    var archiveAsset: ReleaseAsset? {
        assets.first { $0.name == "Lumina-macOS-portable.zip" }
    }

    var checksumAsset: ReleaseAsset? {
        assets.first { $0.name == "Lumina-macOS-portable.zip.sha256" }
    }
}

enum ReleaseUpdateError: LocalizedError {
    case invalidResponse
    case unavailable
    case invalidReleaseVersion
    case releaseArchiveMissing
    case checksumMissing
    case checksumMismatch
    case extractionFailed
    case replacementNotWritable

    var errorDescription: String? {
        switch self {
        case .invalidResponse, .unavailable:
            return NSLocalizedString(
                "Lumina could not check for updates right now.",
                comment: "Release update check error"
            )
        case .invalidReleaseVersion:
            return NSLocalizedString(
                "The latest Lumina release has an invalid version.",
                comment: "Invalid release version error"
            )
        case .releaseArchiveMissing:
            return NSLocalizedString(
                "The latest Lumina release does not contain an installable app.",
                comment: "Missing release archive error"
            )
        case .checksumMissing:
            return NSLocalizedString(
                "The latest Lumina release is missing its checksum.",
                comment: "Missing release checksum error"
            )
        case .checksumMismatch:
            return NSLocalizedString(
                "The downloaded Lumina update failed its checksum check.",
                comment: "Release checksum error"
            )
        case .extractionFailed:
            return NSLocalizedString(
                "The Lumina update could not be unpacked.",
                comment: "Release extraction error"
            )
        case .replacementNotWritable:
            return NSLocalizedString(
                "Lumina cannot update itself in its current folder. Move it to a writable Applications folder and try again.",
                comment: "Release replacement permission error"
            )
        }
    }
}

enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate
    case updateAvailable
    case failed
}

struct ReleaseUpdateService {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/hodadako/lumina/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatestRelease() async throws -> LatestRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "Lumina",
            forHTTPHeaderField: "User-Agent"
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ReleaseUpdateError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ReleaseUpdateError.unavailable
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(LatestRelease.self, from: data)
        } catch {
            throw ReleaseUpdateError.invalidResponse
        }
    }

    func download(_ asset: ReleaseAsset) async throws -> URL {
        var request = URLRequest(url: asset.browserDownloadURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 180
        request.setValue(
            "application/octet-stream",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("Lumina", forHTTPHeaderField: "User-Agent")
        let (url, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw ReleaseUpdateError.unavailable
        }
        return url
    }
}
