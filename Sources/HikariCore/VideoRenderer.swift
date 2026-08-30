import AVFoundation
import Combine
import Foundation
import OSLog

private let playbackLogger = Logger(
    subsystem: "com.hodadako.Hikari",
    category: "Playback"
)

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
    private var itemFailureToken: NSObjectProtocol?
    private var timeControlObservation: NSKeyValueObservation?

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
        load(
            url: currentURL,
            muted: player.isMuted,
            forceReload: true
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
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        currentURL = url
        hasPlaybackError = false
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
        player.removeAllItems()
        currentURL = nil
        isPlaying = false
        hasPlaybackError = false
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
