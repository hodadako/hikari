import Foundation

/// Coalesces automatic selection changes while an Apply or session transition is in progress.
public struct NativeLockSelectionQueue {
    private var pendingID: UUID?

    public init() {}

    public mutating func deferSelection(_ id: UUID) {
        pendingID = id
    }

    public mutating func takeIfReady(currentID: UUID?, available: Bool) -> Bool {
        guard available, let pendingID else { return false }
        self.pendingID = nil
        return pendingID == currentID
    }

    public mutating func cancel() {
        pendingID = nil
    }
}
