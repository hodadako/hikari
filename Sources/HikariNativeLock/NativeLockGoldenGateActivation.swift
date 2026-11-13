import CoreFoundation
import Darwin
import Foundation

public protocol NativeLockAerialPreferences: AnyObject {
    func value(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func synchronize() -> Bool
}

/// Only the two Aerial catalog selection keys are ever changed. Scheduler,
/// update, network and security preferences are deliberately outside this API.
public final class NativeLockLiveAerialPreferences: NativeLockAerialPreferences {
    public static let domain = "com.apple.wallpaper.aerial"
    public init() {}
    public func value(forKey key: String) -> Any? {
        CFPreferencesCopyValue(key as CFString, Self.domain as CFString,
                               kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    public func set(_ value: Any?, forKey key: String) {
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, Self.domain as CFString,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    public func synchronize() -> Bool {
        CFPreferencesSynchronize(Self.domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

/// Golden Gate can ignore the old downloaded schema-1 manifest and load its
/// bundled schema-2 fallback. Give it a separate, user-owned schema-2 catalog;
/// never replace Apple's bundle or the shared macOS 26 downloaded manifest.
public final class NativeLockGoldenGateActivation {
    public static let backupFilename = "Aerial27.activation.original.plist"
    public static let pathKey = "AerialManifestLocalPathOverride"
    public static let forceKey = "AerialManifestForceLocal"
    private let wallpaperRoot: URL
    private let bundledManifest: URL
    private let preferences: NativeLockAerialPreferences
    private let operatingSystemMajorVersion: Int

    public init(wallpaperRoot: URL, bundledManifest: URL, preferences: NativeLockAerialPreferences,
                operatingSystemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.wallpaperRoot = wallpaperRoot
        self.bundledManifest = bundledManifest
        self.preferences = preferences
        self.operatingSystemMajorVersion = operatingSystemMajorVersion
    }

    public static var live: NativeLockGoldenGateActivation {
        Self(wallpaperRoot: NativeLockModernEnvironment.live.wallpaperRootURL,
             bundledManifest: URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/entries.json"),
             preferences: NativeLockLiveAerialPreferences())
    }

    public func catalogURL(for request: NativeLockRequest) -> URL {
        wallpaperRoot.appendingPathComponent("aerials/Hikari/\(request.transactionID.uuidString)/entries.json")
    }

    public func environment(for request: NativeLockRequest) -> NativeLockModernEnvironment {
        NativeLockModernEnvironment(wallpaperRootURL: wallpaperRoot, manifestURL: catalogURL(for: request),
            mediaDirectoryURL: wallpaperRoot.appendingPathComponent("aerials/videos"),
            previewDirectoryURL: wallpaperRoot.appendingPathComponent("aerials/thumbnails"),
            supportedOperatingSystemMajorVersions: [27], operatingSystemMajorVersion: operatingSystemMajorVersion,
            manifestSchemaVersion: 2, previousSelectionManifestURL: previousSelectionManifestURL)
    }

    private var previousSelectionManifestURL: URL? {
        let url = wallpaperRoot.appendingPathComponent("aerials/manifest/entries.json")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Read-only preflight; an existing third-party override is never displaced.
    public func preflight() throws {
        guard operatingSystemMajorVersion == 27 else {
            throw NativeLockTransactionError.unsupportedOperatingSystem(operatingSystemMajorVersion)
        }
        _ = try NativeLockAerialCompatibility.inspect(manifest: Data(contentsOf: bundledManifest),
            wallpaperIndex: Data(contentsOf: wallpaperRoot.appendingPathComponent("Store/Index.plist")), schemaVersion: 2,
            previousSelectionManifest: try previousSelectionManifestURL.map { try Data(contentsOf: $0) })
        if preferences.value(forKey: Self.pathKey) != nil {
            throw NativeLockTransactionError.unsafeSystemPath("Another Aerial catalog override is already configured. Restore it before applying Hikari.")
        }
    }

    /// Creates a durable undo record before shared preference changes. The
    /// caller journals the returned digest before calling activate().
    public func prepare(request: NativeLockRequest, transactionURL: URL) throws -> String {
        try preflight()
        let catalog = try Data(contentsOf: bundledManifest)
        let url = catalogURL(for: request)
        guard !FileManager.default.fileExists(atPath: url.path),
              !FileManager.default.fileExists(atPath: transactionURL.appendingPathComponent(Self.backupFilename).path) else {
            throw NativeLockTransactionError.activeTransactionExists
        }
        var original: [String: Any] = [:]
        for key in [Self.pathKey, Self.forceKey] {
            if let value = preferences.value(forKey: key) { original[key] = value }
        }
        let snapshot: [String: Any] = [
            "schemaVersion": 1, "transactionID": request.transactionID.uuidString,
            "assetID": request.assetID.uuidString, "original": original,
            "catalogPath": url.path, "originalCatalogSHA256": NativeLockDigest.sha256(of: catalog)
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        try durableWrite(data, to: transactionURL.appendingPathComponent(Self.backupFilename), mode: 0o600, directoryMode: 0o700)
        try durableWrite(catalog, to: url, mode: 0o644, directoryMode: 0o755)
        return NativeLockDigest.sha256(of: data)
    }

    public func activate(request: NativeLockRequest, transactionURL: URL, backupSHA256: String) throws {
        let saved = try snapshot(request: request, transactionURL: transactionURL, backupSHA256: backupSHA256)
        guard NSDictionary(dictionary: saved["original"] as! [String: Any]).isEqual(to: currentSelection()) else {
            throw NativeLockTransactionError.transactionMismatch
        }
        let manifest = try NativeLockSafetyInspector.aerialManifest(from: Data(contentsOf: catalogURL(for: request)), schemaVersion: 2)
        guard (manifest["assets"] as? [[String: Any]])?.contains(where: { $0["id"] as? String == request.assetID.uuidString }) == true,
              preferences.value(forKey: Self.pathKey) == nil else {
            throw NativeLockTransactionError.transactionMismatch
        }
        preferences.set(catalogURL(for: request).path, forKey: Self.pathKey)
        preferences.set(true, forKey: Self.forceKey)
        guard preferences.synchronize(), selectionMatches(request: request) else {
            throw NativeLockTransactionError.transactionMismatch
        }
    }

    public func selectionMatches(request: NativeLockRequest) -> Bool {
        preferences.value(forKey: Self.pathKey) as? String == catalogURL(for: request).path
            && preferences.value(forKey: Self.forceKey) as? Bool == true
    }

    public func validateRestore(request: NativeLockRequest, transactionURL: URL, backupSHA256: String) throws {
        _ = try snapshot(request: request, transactionURL: transactionURL, backupSHA256: backupSHA256)
    }

    public func originalCatalogSHA256(request: NativeLockRequest, transactionURL: URL, backupSHA256: String) throws -> String {
        let value = try snapshot(request: request, transactionURL: transactionURL, backupSHA256: backupSHA256)
        guard let hash = value["originalCatalogSHA256"] as? String, NativeLockDigest.isValidSHA256(hash) else {
            throw NativeLockTransactionError.invalidHash
        }
        return hash
    }

    /// Selective preference restore: if another writer selected a different
    /// catalog, it owns the selection now. Never overwrite that pair of keys.
    public func restore(request: NativeLockRequest, transactionURL: URL, backupSHA256: String) throws {
        let value = try snapshot(request: request, transactionURL: transactionURL, backupSHA256: backupSHA256)
        let original = value["original"] as! [String: Any]
        guard preferences.value(forKey: Self.pathKey) as? String == catalogURL(for: request).path else {
            // A previous attempt may have set original values but failed to
            // flush them. Retry synchronization without displacing a new owner.
            guard preferences.synchronize() else { throw NativeLockTransactionError.transactionMismatch }
            return
        }
        var expected = currentSelection()
        expected[Self.pathKey] = original[Self.pathKey]
        preferences.set(original[Self.pathKey], forKey: Self.pathKey)
        if preferences.value(forKey: Self.forceKey) as? Bool == true {
            expected[Self.forceKey] = original[Self.forceKey]
            preferences.set(original[Self.forceKey], forKey: Self.forceKey)
        }
        guard preferences.synchronize(), NSDictionary(dictionary: expected).isEqual(to: currentSelection()) else {
            throw NativeLockTransactionError.transactionMismatch
        }
    }

    private func currentSelection() -> [String: Any] {
        var values: [String: Any] = [:]
        for key in [Self.pathKey, Self.forceKey] {
            if let value = preferences.value(forKey: key) { values[key] = value }
        }
        return values
    }

    private func snapshot(request: NativeLockRequest, transactionURL: URL, backupSHA256: String) throws -> [String: Any] {
        guard operatingSystemMajorVersion == 27 else {
            throw NativeLockTransactionError.unsupportedOperatingSystem(operatingSystemMajorVersion)
        }
        let data = try Data(contentsOf: transactionURL.appendingPathComponent(Self.backupFilename))
        guard NativeLockDigest.isValidSHA256(backupSHA256), NativeLockDigest.sha256(of: data) == backupSHA256,
              let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              value["schemaVersion"] as? Int == 1,
              value["transactionID"] as? String == request.transactionID.uuidString,
              value["assetID"] as? String == request.assetID.uuidString,
              value["catalogPath"] as? String == catalogURL(for: request).path,
              value["original"] is [String: Any] else {
            throw NativeLockTransactionError.invalidHash
        }
        return value
    }

    private func durableWrite(_ data: Data, to url: URL, mode: Int, directoryMode: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: directoryMode])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        for (path, flags) in [(url.path, O_RDONLY | O_NOFOLLOW), (url.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)] {
            let fd = open(path, flags)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let result = fsync(fd)
            let savedErrno = errno
            close(fd)
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: savedErrno) ?? .EIO) }
        }
    }
}
