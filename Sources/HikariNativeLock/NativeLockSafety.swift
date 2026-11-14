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
    /// Product enablement, explicitly requested for the 0.5.3 release.
    /// This does not assert that every live Lock Screen scenario is validated.
    /// Schema, ownership, backup and originating-OS checks remain mandatory.
    public static let goldenGateNativeLockEnabled = true
    public static var current: Self {
        Self(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    public let majorVersion: Int
    private let isGoldenGateNativeLockEnabled: Bool

    /// Creates an injectable runtime policy without probing or modifying live stores.
    public init(
        majorVersion: Int,
        goldenGateNativeLockEnabled: Bool = Self.goldenGateNativeLockEnabled
    ) {
        self.majorVersion = majorVersion
        self.isGoldenGateNativeLockEnabled = goldenGateNativeLockEnabled
    }

    public var writeBackend: NativeLockTransactionBackend? {
        switch majorVersion {
        case 15: .systemCatalog
        case 26: .userAerials
        case 27: isGoldenGateNativeLockEnabled ? .userAerials27 : nil
        default: nil
        }
    }

    /// Allows a recorded backend only on its reviewed runtime.
    /// A missing backend remains compatible with pre-split macOS 15 journals.
    public func canModifyTransaction(
        backend: NativeLockTransactionBackend?,
        operatingSystemMajorVersion: Int? = nil
    ) -> Bool {
        switch writeBackend {
        case .systemCatalog:
            (backend == nil || backend == .systemCatalog)
                && (operatingSystemMajorVersion == nil || operatingSystemMajorVersion == 15)
        case .userAerials:
            backend == .userAerials && (operatingSystemMajorVersion ?? 26) == 26
        case .userAerials27:
            backend == .userAerials27 && operatingSystemMajorVersion == 27
        case nil: false
        }
    }

    /// Only explicit Restore may cross the reviewed 26 → 27 user-store boundary.
    /// The controller must validate both backups and the current store first,
    /// and must merge into the current topology rather than replay the old index.
    public func requiresUpgradeRestore(
        backend: NativeLockTransactionBackend?,
        operatingSystemMajorVersion: Int?
    ) -> Bool {
        writeBackend == .userAerials27 && backend == .userAerials
            && [26, 27].contains(operatingSystemMajorVersion ?? 26)
    }
}

/// Evaluates prerequisites without elevated privileges. The separate system
/// transaction manager repeats the OS and schema checks before every write.
public enum NativeLockSafetyInspector {
    /// Returns whether the macOS 26 per-user Aerial manifest exists and has
    /// the expected schema. Reads only the manifest.
    public static func aerialManifestState(
        manifestURL: URL, schemaVersion: Int = 1
    ) -> AerialManifestState {
        do {
            _ = try aerialManifest(from: Data(contentsOf: manifestURL), schemaVersion: schemaVersion)
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

    /// Parses the expected schema and record arrays, rejecting Boolean version values.
    /// Throws before a caller can modify an unrecognized manifest.
    static func aerialManifest(from data: Data, schemaVersion: Int = 1) throws -> [String: Any] {
        guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = manifest["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == Double(schemaVersion),
              manifest["assets"] is [[String: Any]],
              manifest["categories"] is [[String: Any]] else {
            throw NativeLockTransactionError.invalidWallpaperStore
        }
        return manifest
    }

    /// Reports runtime support, saved recovery state and media/store prerequisites.
    /// Preservation takes priority when an unfinished journal cannot be modified
    /// on this runtime, even if the manifest itself has a recognized schema.
    public static func evaluate(
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        hasSelectedMedia: Bool,
        transactionPhase: NativeLockTransactionPhase? = nil,
        transactionBackend: NativeLockTransactionBackend? = nil,
        transactionOperatingSystemMajorVersion: Int? = nil,
        aerialManifestURL: URL? = nil,
        aerialWallpaperIndexURL: URL? = nil,
        goldenGateNativeLockEnabled: Bool = NativeLockOperatingSystemPolicy.goldenGateNativeLockEnabled
    ) -> NativeLockSafetyReport {
        let policy = NativeLockOperatingSystemPolicy(
            majorVersion: operatingSystemVersion.majorVersion,
            goldenGateNativeLockEnabled: goldenGateNativeLockEnabled
        )
        if NativeLockUpgradeGuard.requiresRestoreBeforeMajorOperatingSystemUpdate(
            transactionPhase: transactionPhase
        ), policy.requiresUpgradeRestore(
            backend: transactionBackend,
            operatingSystemMajorVersion: transactionOperatingSystemMajorVersion
        ) {
            return NativeLockSafetyReport(
                state: .recoveryRequired,
                title: "Lock Screen recovery required",
                detail: "Restore the previous macOS transaction before selecting another Lock Screen video. Hikari validates the saved backups and preserves the current display and Space layout."
            )
        }
        if NativeLockUpgradeGuard.requiresRestoreBeforeMajorOperatingSystemUpdate(
            transactionPhase: transactionPhase
        ), !policy.canModifyTransaction(
            backend: transactionBackend,
            operatingSystemMajorVersion: transactionOperatingSystemMajorVersion
        ) {
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
        if backend.isUserAerials {
            let manifestURL = aerialManifestURL ?? (backend == .userAerials27
                ? URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/entries.json")
                : NativeLockModernEnvironment.live.manifestURL)
            let schemaVersion = backend == .userAerials27 ? 2 : 1
            switch aerialManifestState(manifestURL: manifestURL, schemaVersion: schemaVersion) {
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
            if policy.majorVersion == 27 {
                let indexURL = aerialWallpaperIndexURL
                    ?? NativeLockModernEnvironment.live.wallpaperRootURL.appendingPathComponent("Store/Index.plist")
                do {
                    _ = try NativeLockAerialCompatibility.inspect(
                        manifest: Data(contentsOf: manifestURL),
                        wallpaperIndex: Data(contentsOf: indexURL), schemaVersion: schemaVersion,
                        previousSelectionManifest: aerialManifestURL == nil
                            ? try? Data(contentsOf: NativeLockModernEnvironment.live.manifestURL) : nil
                    )
                } catch {
                    return NativeLockSafetyReport(
                        state: .aerialCatalogRequired,
                        title: "Aerial wallpaper store is not recognized",
                        detail: "Select an Apple Aerial wallpaper in System Settings to initialize its Lock Screen selection. Hikari will not create an unverified wallpaper layout."
                    )
                }
            }
        }

        guard hasSelectedMedia else {
            return NativeLockSafetyReport(
                state: .mediaRequired,
                title: "Import a video first",
                detail: "The selected video remains in Hikari's private application-support directory."
            )
        }

        let detail = backend.isUserAerials
            ? "Applying uses the verified user Aerial catalog and creates rollback records without administrator approval."
            : "Applying requires administrator approval and creates verified user and system rollback records."
        return NativeLockSafetyReport(
            state: .ready,
            title: "Ready to apply locally",
            detail: detail
        )
    }
}
