import Foundation

public struct LiveContent: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public let relativePath: String
    public let fileSize: Int64
    public let duration: Double
    public let width: Int
    public let height: Int
    public let codec: String?
    public let thumbnailRelativePath: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        relativePath: String,
        fileSize: Int64,
        duration: Double,
        width: Int,
        height: Int,
        codec: String?,
        thumbnailRelativePath: String?,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.relativePath = relativePath
        self.fileSize = fileSize
        self.duration = duration
        self.width = width
        self.height = height
        self.codec = codec
        self.thumbnailRelativePath = thumbnailRelativePath
        self.createdAt = createdAt
    }
}

public enum PlaybackPreference: String, Codable, CaseIterable, Sendable {
    case playing
    case paused
}

public enum ScalingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case fill
    case fit

    public var id: String { rawValue }
}

public enum AppIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case hikari
    case custom

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == Self.custom.rawValue ? .custom : .hikari
    }
}

public enum MenuBarIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case hikari
    case custom

    public var id: String { rawValue }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = value == Self.custom.rawValue ? .custom : .hikari
    }
}

public struct HikariSettings: Codable, Equatable, Sendable {
    public var selectedContentID: UUID?
    /// The last folder from which the user selected a video. The picker
    /// falls back to the user's home directory when this folder no longer
    /// exists.
    public var lastVideoPickerDirectoryPath: String?
    public var playbackPreference: PlaybackPreference
    public var scalingMode: ScalingMode
    public var isMuted: Bool
    public var pauseOnBattery: Bool
    public var launchAtLogin: Bool
    public var lastKnownScreenSaverInstalled: Bool
    public var appIconStyle: AppIconStyle
    public var customAppIconRelativePath: String?
    public var menuBarIconStyle: MenuBarIconStyle
    public var customMenuBarIconRelativePath: String?
    public var overrideSystemLockShortcut: Bool
    /// Legacy compatibility field; Hikari uses Native Lock directly.
    public var lockScreenPlaybackEnabled: Bool
    /// Legacy screen saver compatibility field retained for old settings.
    public var screenSaverPreviousIdleTime: Int?

    public init(
        selectedContentID: UUID? = nil,
        lastVideoPickerDirectoryPath: String? = nil,
        playbackPreference: PlaybackPreference = .playing,
        scalingMode: ScalingMode = .fill,
        isMuted: Bool = true,
        pauseOnBattery: Bool = false,
        launchAtLogin: Bool = false,
        lastKnownScreenSaverInstalled: Bool = false,
        appIconStyle: AppIconStyle = .hikari,
        customAppIconRelativePath: String? = nil,
        menuBarIconStyle: MenuBarIconStyle = .hikari,
        customMenuBarIconRelativePath: String? = nil,
        overrideSystemLockShortcut: Bool = false,
        lockScreenPlaybackEnabled: Bool = false,
        screenSaverPreviousIdleTime: Int? = nil
    ) {
        self.selectedContentID = selectedContentID
        self.lastVideoPickerDirectoryPath = lastVideoPickerDirectoryPath
        self.playbackPreference = playbackPreference
        self.scalingMode = scalingMode
        self.isMuted = isMuted
        self.pauseOnBattery = pauseOnBattery
        self.launchAtLogin = launchAtLogin
        self.lastKnownScreenSaverInstalled = lastKnownScreenSaverInstalled
        self.appIconStyle = appIconStyle
        self.customAppIconRelativePath = customAppIconRelativePath
        self.menuBarIconStyle = menuBarIconStyle
        self.customMenuBarIconRelativePath = customMenuBarIconRelativePath
        self.overrideSystemLockShortcut = overrideSystemLockShortcut
        self.lockScreenPlaybackEnabled = lockScreenPlaybackEnabled
        self.screenSaverPreviousIdleTime = screenSaverPreviousIdleTime
    }

    private enum CodingKeys: String, CodingKey {
        case selectedContentID
        case lastVideoPickerDirectoryPath
        case playbackPreference
        case scalingMode
        case isMuted
        case pauseOnBattery
        case launchAtLogin
        case lastKnownScreenSaverInstalled
        case appIconStyle
        case customAppIconRelativePath
        case menuBarIconStyle
        case customMenuBarIconRelativePath
        case overrideSystemLockShortcut
        case lockScreenPlaybackEnabled
        case screenSaverPreviousIdleTime
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        selectedContentID = try values.decodeIfPresent(
            UUID.self,
            forKey: .selectedContentID
        )
        lastVideoPickerDirectoryPath = try values.decodeIfPresent(
            String.self,
            forKey: .lastVideoPickerDirectoryPath
        )
        playbackPreference = try values.decodeIfPresent(
            PlaybackPreference.self,
            forKey: .playbackPreference
        ) ?? .playing
        scalingMode = try values.decodeIfPresent(
            ScalingMode.self,
            forKey: .scalingMode
        ) ?? .fill
        isMuted = try values.decodeIfPresent(Bool.self, forKey: .isMuted) ?? true
        pauseOnBattery = try values.decodeIfPresent(
            Bool.self,
            forKey: .pauseOnBattery
        ) ?? false
        launchAtLogin = try values.decodeIfPresent(
            Bool.self,
            forKey: .launchAtLogin
        ) ?? false
        lastKnownScreenSaverInstalled = try values.decodeIfPresent(
            Bool.self,
            forKey: .lastKnownScreenSaverInstalled
        ) ?? false
        appIconStyle = try values.decodeIfPresent(
            AppIconStyle.self,
            forKey: .appIconStyle
        ) ?? .hikari
        customAppIconRelativePath = try values.decodeIfPresent(
            String.self,
            forKey: .customAppIconRelativePath
        )
        menuBarIconStyle = try values.decodeIfPresent(
            MenuBarIconStyle.self,
            forKey: .menuBarIconStyle
        ) ?? .hikari
        customMenuBarIconRelativePath = try values.decodeIfPresent(
            String.self,
            forKey: .customMenuBarIconRelativePath
        )
        overrideSystemLockShortcut = try values.decodeIfPresent(
            Bool.self,
            forKey: .overrideSystemLockShortcut
        ) ?? false
        lockScreenPlaybackEnabled = try values.decodeIfPresent(
            Bool.self,
            forKey: .lockScreenPlaybackEnabled
        ) ?? false
        screenSaverPreviousIdleTime = try values.decodeIfPresent(
            Int.self,
            forKey: .screenSaverPreviousIdleTime
        )
    }
}

public enum PlaybackPauseReason: Hashable, Sendable {
    case user
    case battery
    case screenLock
    case screenSaver
    case sleep
    case noContent
}

public enum HikariError: LocalizedError, Equatable {
    case unsupportedFile
    case unreadableVideo
    case duplicateContent
    case fileCopyFailed(String)
    case contentNotFound
    case screenSaverBundleMissing

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            return NSLocalizedString(
                "Choose a video file that macOS recognizes as a movie.",
                comment: ""
            )
        case .unreadableVideo:
            return NSLocalizedString(
                "This video cannot be read or does not contain a playable video track.",
                comment: ""
            )
        case .duplicateContent:
            return NSLocalizedString(
                "This video is already in your Hikari library.",
                comment: ""
            )
        case let .fileCopyFailed(reason):
            return String(
                format: NSLocalizedString(
                    "The video could not be copied: %@",
                    comment: ""
                ),
                reason
            )
        case .contentNotFound:
            return NSLocalizedString(
                "The selected video is no longer available.",
                comment: ""
            )
        case .screenSaverBundleMissing:
            return NSLocalizedString(
                "The legacy screen saver is missing from this app build.",
                comment: ""
            )
        }
    }
}
