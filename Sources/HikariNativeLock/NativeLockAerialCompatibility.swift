import Foundation

/// Read-only checks for the user Aerial contract observed on Golden Gate.
/// Schema recognition and runtime lifecycle validation are separate requirements.
/// This does not create a manifest, materialize topology, or signal a service.
public enum NativeLockAerialCompatibility {
    public struct Snapshot: Equatable, Sendable {
        public let linkedChoiceCount: Int
        public let manifestSHA256: String
        public let wallpaperIndexSHA256: String
    }

    public static func inspect(manifest: Data, wallpaperIndex: Data) throws -> Snapshot {
        let catalog = try NativeLockSafetyInspector.aerialManifest(from: manifest)
        guard let assets = catalog["assets"] as? [[String: Any]],
              let index = try PropertyListSerialization.propertyList(
                from: wallpaperIndex, options: [], format: nil
              ) as? [String: Any],
              index["SystemDefault"] is [String: Any],
              index["Displays"] is [String: Any],
              index["Spaces"] is [String: Any] else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        let assetIDs = Set(assets.compactMap { $0["id"] as? String })
        var count = 0
        try visit(index, assetIDs: assetIDs, count: &count)
        guard count > 0 else { throw NativeLockTransactionError.noWallpaperChoices }
        return Snapshot(
            linkedChoiceCount: count,
            manifestSHA256: NativeLockDigest.sha256(of: manifest),
            wallpaperIndexSHA256: NativeLockDigest.sha256(of: wallpaperIndex)
        )
    }

    private static func visit(_ value: Any, assetIDs: Set<String>, count: inout Int) throws {
        if let dictionary = value as? [String: Any] {
            if let linked = dictionary["Linked"] {
                guard let container = linked as? [String: Any],
                      let content = container["Content"] as? [String: Any],
                      let choices = content["Choices"] as? [[String: Any]],
                      choices.count == 1,
                      let choice = choices.first,
                      choice["Provider"] as? String == "com.apple.wallpaper.choice.aerials",
                      let configuration = choice["Configuration"] as? Data,
                      let decoded = try PropertyListSerialization.propertyList(
                        from: configuration, options: [], format: nil
                      ) as? [String: Any],
                      let assetID = decoded["assetID"] as? String,
                      UUID(uuidString: assetID) != nil,
                      assetIDs.contains(assetID),
                      let options = content["EncodedOptionValues"] as? Data,
                      let decodedOptions = try PropertyListSerialization.propertyList(
                        from: options, options: [], format: nil
                      ) as? [String: Any],
                      let values = decodedOptions["values"] as? [String: Any],
                      let placement = values["placement"] as? [String: Any],
                      let picker = placement["picker"] as? [String: Any],
                      let selected = picker["_0"] as? [String: Any],
                      let placementID = selected["id"] as? String,
                      !placementID.isEmpty else {
                    throw NativeLockTransactionError.invalidWallpaperStore
                }
                count += 1
            }
            for child in dictionary.values { try visit(child, assetIDs: assetIDs, count: &count) }
        } else if let array = value as? [Any] {
            for child in array { try visit(child, assetIDs: assetIDs, count: &count) }
        }
    }
}
