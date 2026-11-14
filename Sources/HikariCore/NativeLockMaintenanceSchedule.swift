import Foundation

/// Monotonic unlock settling shared by the timer and periodic maintenance.
/// A request left over from a previous lock cycle cannot bypass a newer delay.
public struct NativeLockMaintenanceSchedule {
    public private(set) var refreshRequested = false
    private var notBefore: TimeInterval?

    public init() {}

    public mutating func requestRefresh() {
        refreshRequested = true
    }

    public mutating func didUnlock(at uptime: TimeInterval) {
        refreshRequested = true
        notBefore = uptime + 2
    }

    public func permitsMaintenance(at uptime: TimeInterval) -> Bool {
        notBefore.map { uptime >= $0 } ?? true
    }

    public mutating func consumeRefresh() -> Bool {
        let requested = refreshRequested
        refreshRequested = false
        return requested
    }

    public mutating func cancel() {
        refreshRequested = false
        notBefore = nil
    }
}
