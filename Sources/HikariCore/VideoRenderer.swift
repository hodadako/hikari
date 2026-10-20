import AVFoundation
import Combine
import Foundation
import OSLog

private let playbackLogger = Logger(
    subsystem: "com.hodadako.Hikari",
    category: "Playback"
)

struct PlaybackItemHealth {
    private var missingSince: Date?

    mutating func needsRecovery(hasItem: Bool, itemFailed: Bool, now: Date) -> Bool {
        if itemFailed {
            missingSince = nil
            return true
        }
        if hasItem {
            missingSince = nil
            return false
        }
        guard let missingSince else {
            missingSince = now
            return false
        }
        return now.timeIntervalSince(missingSince) >= 5
    }

    mutating func reset() {
        missingSince = nil
    }
}

@MainActor
public final class VideoRenderer: ObservableObject, PlaybackSession {
    /// Keep only a short local-file buffer. Longer buffers increase memory use
    /// and raise the chance of a visible stall while a wallpaper recovers.
    public static let preferredForwardBufferDuration: TimeInterval = 1

    @Published public private(set) var currentURL: URL?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var hasPlaybackError = false

    public let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var loadStartedAt: ContinuousClock.Instant?
    private var itemFailureToken: NSObjectProtocol?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemHealth = PlaybackItemHealth()

    public init() {
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        observePlaybackState()
    }

    public func load(url: URL, muted: Bool) {
        load(url: url, muted: muted, forceReload: false)
    }

    /// Recreate a failed item without changing the shared player that feeds
    /// every display layer.
    public func reloadCurrentItem() {
        guard let currentURL else { return }
        playbackLogger.notice("Rebuilding selected video's playback queue")
        load(
            url: currentURL,
            muted: player.isMuted,
            forceReload: true
        )
    }

    /// A wake can leave the queue without an item while the URL and looper
    /// still look valid. Allow transient queue changes to settle first.
    public var requiresPlaybackRecovery: Bool {
        guard currentURL != nil, looper != nil else {
            itemHealth.reset()
            return false
        }
        if hasPlaybackError || looper?.status == .failed {
            return true
        }
        return itemHealth.needsRecovery(
            hasItem: player.currentItem != nil,
            itemFailed: player.currentItem?.status == .failed,
            now: Date()
        )
    }

    private func load(url: URL, muted: Bool, forceReload: Bool) {
        guard forceReload || currentURL != url else {
            player.isMuted = muted
            return
        }
        stopAndRelease()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = Self.preferredForwardBufferDuration
        itemFailureToken = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hasPlaybackError = true
                self?.isPlaying = false
            }
        }
        loadStartedAt = ContinuousClock.now
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        currentURL = url
        hasPlaybackError = false
        itemHealth.reset()
    }

    public func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    public func play() {
        guard currentURL != nil else { return }
        player.play()
    }

    public func pause() {
        player.pause()
        isPlaying = false
    }

    public var currentTime: Double {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? seconds : 0
    }

    public func seek(to seconds: Double) {
        guard seconds.isFinite else { return }
        player.seek(
            to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    public func stopAndRelease() {
        player.pause()
        if let itemFailureToken {
            NotificationCenter.default.removeObserver(itemFailureToken)
            self.itemFailureToken = nil
        }
        looper?.disableLooping()
        looper = nil
        loadStartedAt = nil
        player.removeAllItems()
        currentURL = nil
        isPlaying = false
        hasPlaybackError = false
        itemHealth.reset()
    }

    public func releaseResources() {
        stopAndRelease()
    }

    private func observePlaybackState() {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.initial, .new]
        ) { [weak self] player, _ in
            let isPlaying = player.timeControlStatus == .playing
            let status = String(describing: player.timeControlStatus)
            let waitingReason = player.reasonForWaitingToPlay?.rawValue ?? "none"
            Task { @MainActor [weak self] in
                self?.isPlaying = isPlaying
                playbackLogger.debug(
                    "AVPlayer state=\(status, privacy: .public) waitingReason=\(waitingReason, privacy: .public)"
                )
            }
        }
    }

    deinit {
        timeControlObservation?.invalidate()
        player.pause()
        if let itemFailureToken {
            NotificationCenter.default.removeObserver(itemFailureToken)
        }
        looper?.disableLooping()
        player.removeAllItems()
    }
}
