import Foundation

public struct PlaybackPolicy: Equatable, Sendable {
    public var userWantsPlayback: Bool
    public var pauseOnBattery: Bool
    public var isOnBattery: Bool
    public var isScreenLocked: Bool
    public var isScreenSaverRunning: Bool
    public var isSleeping: Bool
    public var hasContent: Bool

    public init(
        userWantsPlayback: Bool = true,
        pauseOnBattery: Bool = false,
        isOnBattery: Bool = false,
        isScreenLocked: Bool = false,
        isScreenSaverRunning: Bool = false,
        isSleeping: Bool = false,
        hasContent: Bool = false
    ) {
        self.userWantsPlayback = userWantsPlayback
        self.pauseOnBattery = pauseOnBattery
        self.isOnBattery = isOnBattery
        self.isScreenLocked = isScreenLocked
        self.isScreenSaverRunning = isScreenSaverRunning
        self.isSleeping = isSleeping
        self.hasContent = hasContent
    }

    public var pauseReasons: Set<PlaybackPauseReason> {
        var reasons = Set<PlaybackPauseReason>()
        if !userWantsPlayback { reasons.insert(.user) }
        if pauseOnBattery && isOnBattery { reasons.insert(.battery) }
        if isScreenLocked { reasons.insert(.screenLock) }
        if isScreenSaverRunning { reasons.insert(.screenSaver) }
        if isSleeping { reasons.insert(.sleep) }
        if !hasContent { reasons.insert(.noContent) }
        return reasons
    }

    public var shouldPlay: Bool {
        pauseReasons.isEmpty
    }
}
