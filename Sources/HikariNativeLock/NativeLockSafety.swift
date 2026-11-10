import CoreFoundation
import Foundation

public enum NativeLockSafetyState: String, Codable, Sendable {
    case unsupportedOperatingSystem
    case transactionPreserved
    /// macOS 26: the per-user Aerial catalog has not been initialized.
    case aerialCatalogRequired
    case mediaRequired
    case ready
    case active
    case recoveryRequired
}

public struct NativeLockSafetyReport: Equatable, Sendable {
    public let state: NativeLockSafetyState
    public let title: String
    public let detail: String

    public init(state: NativeLockSafetyState, title: String, detail: String) {
        self.state = state
        self.title = title
        self.detail = detail
    }
}

/// A Native Lock transaction must be restored before an operating-system
/// major-version update. The system catalog and its service lifecycle can
/// change across major versions, so an unfinished transaction must not be
/// carried into an unreviewed environment.
public enum NativeLockUpgradeGuard {
    public static func requiresRestoreBeforeMajorOperatingSystemUpdate(
        transactionPhase: NativeLockTransactionPhase?
    ) -> Bool {
        guard let transactionPhase else { return false }
        return transactionPhase != .restored
    }
}

/// Selects reviewed write backends independently of the live store schema.
public struct NativeLockOperatingSystemPolicy: Sendable {
    public static var current: Self {
        Self(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    public let majorVersion: Int

    public init(majorVersion: Int) {
        self.majorVersion = majorVersion
    }

    public var writeBackend: NativeLockTransactionBackend? {
        switch majorVersion {
        case 15: .systemCatalog
        case 26: .userAerials
        default: nil
        }
    }

    public func canModifyTransaction(backend: NativeLockTransactionBackend?) -> Bool {
        switch writeBackend {
        case .systemCatalog: backend == nil || backend == .systemCatalog
        case .userAerials: backend == .userAerials
        case nil: false
        }
    }
}

/// Evaluates prerequisites without elevated privileges. The separate system
/// transaction manager repeats the OS and schema checks before every write.
public enum NativeLockSafetyInspector {
    /// Returns whether the macOS 26 per-user Aerial manifest exists and has
    /// the expected schema. Reads only the manifest.
    public static func aerialManifestState(
        manifestURL: URL
    ) -> AerialManifestState {
        do {
            _ = try aerialManifest(from: Data(contentsOf: manifestURL))
            return .ready
        } catch CocoaError.fileReadNoSuchFile {
            return .missing
        } catch {
            return .invalid
        }
    }

    public enum AerialManifestState {
        case ready
        case missing
        case invalid
    }

    static func aerialManifest(from data: Data) throws -> [String: Any] {
        guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = manifest["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == 1,
              manifest["assets"] is [[String: Any]],
              manifest["categories"] is [[String: Any]] else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        return manifest
    }

    public static func evaluate(
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        hasSelectedMedia: Bool,
        transactionPhase: NativeLockTransactionPhase? = nil,
        transactionBackend: NativeLockTransactionBackend? = nil,
        aerialManifestURL: URL? = nil
    ) -> NativeLockSafetyReport {
        let policy = NativeLockOperatingSystemPolicy(
            majorVersion: operatingSystemVersion.majorVersion
        )
        if NativeLockUpgradeGuard.requiresRestoreBeforeMajorOperatingSystemUpdate(
            transactionPhase: transactionPhase
        ), !policy.canModifyTransaction(backend: transactionBackend) {
            return NativeLockSafetyReport(
                state: .transactionPreserved,
                title: "Saved Lock Screen transaction",
                detail: "Hikari has kept the transaction and its backups. To restore it, use Hikari on the macOS version that created it, with the matching wallpaper store."
            )
        }

        guard let backend = policy.writeBackend else {
            return NativeLockSafetyReport(
                state: .unsupportedOperatingSystem,
                title: "Native Lock is unavailable on this macOS version",
                detail: "Desktop video is available. Lock Screen changes require a verified macOS wallpaper backend."
            )
        }

        if let transactionPhase,
           transactionPhase != .active,
           transactionPhase != .restored {
            return NativeLockSafetyReport(
                state: .recoveryRequired,
                title: "Lock Screen recovery required",
                detail: "Restore the saved wallpaper state before applying another video."
            )
        }

        if transactionPhase == .active {
            return NativeLockSafetyReport(
                state: .active,
                title: "Lock Screen is active",
                detail: "The macOS-owned Lock Screen uses the staged Hikari video."
            )
        }

        // On macOS 26, verify the Aerial catalog exists before allowing Apply.
        if backend == .userAerials {
            let manifestURL = aerialManifestURL ?? NativeLockModernEnvironment.live.manifestURL
            switch aerialManifestState(manifestURL: manifestURL) {
            case .missing:
                return NativeLockSafetyReport(
                    state: .aerialCatalogRequired,
                    title: "Initialize Apple Aerial wallpapers first",
                    detail: "Download or select an Apple Aerial wallpaper in System Settings → Wallpaper before applying Native Lock."
                )
            case .invalid:
                return NativeLockSafetyReport(
                    state: .aerialCatalogRequired,
                    title: "Aerial wallpaper store is not recognized",
                    detail: "Hikari could not read the expected Aerial manifest. Check its availability in System Settings → Wallpaper."
                )
            case .ready:
                break
            }
        }

        guard hasSelectedMedia else {
            return NativeLockSafetyReport(
                state: .mediaRequired,
                title: "Import a video first",
                detail: "The selected video remains in Hikari's private application-support directory."
            )
        }

        let detail = backend == .userAerials
            ? "Applying uses the verified macOS 26 user Aerial catalog and creates rollback records without administrator approval."
            : "Applying requires administrator approval and creates verified user and system rollback records."
        return NativeLockSafetyReport(
            state: .ready,
            title: "Ready to apply locally",
            detail: detail
        )
    }
}
