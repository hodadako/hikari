import Foundation

public enum NativeLockSafetyState: String, Codable, Sendable {
    case unsupportedOperatingSystem
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

/// Evaluates prerequisites without elevated privileges. The separate system
/// transaction manager repeats the OS and schema checks before every write.
public enum NativeLockSafetyInspector {
    public static func evaluate(
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        hasSelectedMedia: Bool,
        transactionPhase: NativeLockTransactionPhase? = nil
    ) -> NativeLockSafetyReport {
        guard operatingSystemVersion.majorVersion == 15 else {
            return NativeLockSafetyReport(
                state: .unsupportedOperatingSystem,
                title: "Reviewed macOS 15 build required",
                detail: "Native Lock writes are disabled until this macOS major version's wallpaper schema is reviewed."
            )
        }

        if let transactionPhase,
           transactionPhase != .active,
           transactionPhase != .restored {
            return NativeLockSafetyReport(
                state: .recoveryRequired,
                title: "Native Lock recovery required",
                detail: "Restore the saved wallpaper state before applying another video."
            )
        }

        if transactionPhase == .active {
            return NativeLockSafetyReport(
                state: .active,
                title: "Native Lock is active",
                detail: "The macOS-owned Lock Screen uses the staged Hikari video."
            )
        }

        guard hasSelectedMedia else {
            return NativeLockSafetyReport(
                state: .mediaRequired,
                title: "Import a video first",
                detail: "The selected video remains in Hikari's private application-support directory."
            )
        }

        return NativeLockSafetyReport(
            state: .ready,
            title: "Ready to apply locally",
            detail: "Applying requires administrator approval and creates verified user and system rollback records."
        )
    }
}
