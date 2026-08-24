import Foundation

/// Persists the user's pre-Lumina screen saver delay so disabling the opt-in
/// feature can restore it exactly instead of guessing with `idleTime = 0`.
public struct ScreenSaverIdleTimePolicy: Codable, Equatable, Sendable {
    public var originalIdleTime: Int?

    public init(originalIdleTime: Int? = nil) {
        self.originalIdleTime = originalIdleTime
    }

    public mutating func enable(currentIdleTime: Int) -> Int {
        if originalIdleTime == nil {
            originalIdleTime = currentIdleTime
        }
        return 60
    }

    public mutating func disable(fallbackIdleTime: Int = 0) -> Int {
        defer { originalIdleTime = nil }
        return originalIdleTime ?? fallbackIdleTime
    }
}
