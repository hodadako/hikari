import Foundation
import UniformTypeIdentifiers

public enum VideoFileSupport {
    /// Let AppKit expose every container macOS identifies as a movie. The
    /// importer still asks AVFoundation whether the selected asset is actually
    /// playable and contains a video track before accepting it.
    public static let pickerContentTypes: [UTType] = [.movie]

    public static func storageFileExtension(for sourceURL: URL) -> String? {
        let declaredType = try? sourceURL.resourceValues(
            forKeys: [.contentTypeKey]
        ).contentType
        let filenameType = UTType(filenameExtension: sourceURL.pathExtension)
        guard let movieType = declaredType ?? filenameType,
              movieType.conforms(to: .movie) else {
            return nil
        }

        let candidates = [
            sourceURL.pathExtension,
            movieType.preferredFilenameExtension ?? ""
        ]
        for candidate in candidates {
            let normalized = candidate.lowercased()
            guard !normalized.isEmpty,
                  normalized.count <= 16,
                  normalized.unicodeScalars.allSatisfy({
                      CharacterSet.alphanumerics.contains($0)
                  }) else {
                continue
            }
            return normalized
        }
        return nil
    }
}
