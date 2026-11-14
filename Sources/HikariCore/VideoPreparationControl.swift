import Foundation

/// Cooperative cancellation and bounded progress delivery for background encoders.
/// GCD/VideoToolbox callbacks cannot rely on the caller's Swift task cancellation.
public final class VideoPreparationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var lastProgress = 0.0
    private var lastDelivery = 0.0
    private let onProgress: @Sendable (Double) -> Void

    public init(onProgress: @escaping @Sendable (Double) -> Void = { _ in }) {
        self.onProgress = onProgress
    }

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public func checkCancellation() throws {
        lock.lock()
        let isCancelled = cancelled
        lock.unlock()
        if isCancelled || Task<Never, Never>.isCancelled { throw CancellationError() }
    }

    /// At most five UI updates per second; never regress or report non-finite values.
    public func reportProgress(_ value: Double) {
        guard value.isFinite else { return }
        let fraction = min(1, max(0, value))
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !cancelled, fraction > lastProgress,
              fraction == 1 || (fraction - lastProgress >= 0.01 && now - lastDelivery >= 0.2) else {
            lock.unlock()
            return
        }
        lastProgress = fraction
        lastDelivery = now
        lock.unlock()
        onProgress(fraction)
    }
}
