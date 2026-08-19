import Foundation

public enum NativeLockSafetyState: String, Codable, Sendable {
    case unsupportedOperatingSystem
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

/// Evaluates prerequisites without elevated privileges. The separate system
/// transaction manager repeats the OS and schema checks before every write.
public enum NativeLockSafetyInspector {
    /// Returns whether the macOS 26 per-user Aerial manifest exists and has
    /// the expected schema. Does not read or modify any wallpaper state.
    public static func aerialManifestState(
        manifestURL: URL
    ) -> AerialManifestState {
        guard let data = try? Data(contentsOf: manifestURL) else {
            return .missing
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["version"] as? Int == 1,
              root["assets"] is [[String: Any]],
              root["categories"] is [[String: Any]] else {
            return .invalid
        }
        return .ready
    }

    public enum AerialManifestState {
        case ready
        case missing
        case invalid
    }

    public static func evaluate(
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        hasSelectedMedia: Bool,
        transactionPhase: NativeLockTransactionPhase? = nil,
        aerialManifestURL: URL? = nil
    ) -> NativeLockSafetyReport {
        let majorVersion = operatingSystemVersion.majorVersion
        guard majorVersion == 15 || majorVersion == 26 else {
            return NativeLockSafetyReport(
                state: .unsupportedOperatingSystem,
                title: "Reviewed macOS 15 or 26 build required",
                detail: "Lock Screen changes are disabled until this macOS major version is reviewed."
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
        if majorVersion == 26 {
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
                    detail: "The macOS Aerial manifest exists but does not match the expected schema. Native Lock cannot modify an unrecognized store."
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

        let detail = majorVersion == 26
            ? "Applying uses the verified macOS 26 user Aerial catalog and creates rollback records without administrator approval."
            : "Applying requires administrator approval and creates verified user and system rollback records."
        return NativeLockSafetyReport(
            state: .ready,
            title: "Ready to apply locally",
            detail: detail
        )
    }
}
