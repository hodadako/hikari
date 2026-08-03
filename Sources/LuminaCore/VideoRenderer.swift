import AVFoundation
import Combine
import Foundation

@MainActor
public final class VideoRenderer: ObservableObject, PlaybackSession {
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var isPlaying = false
    @Published public private(set) var hasPlaybackError = false

    public let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var itemFailureToken: NSObjectProtocol?

    public init() {
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
    }

    public func load(url: URL, muted: Bool) {
        guard currentURL != url else {
            player.isMuted = muted
            return
        }
        stopAndRelease()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = 2
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
        isPlaying = true
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

    deinit {
        player.pause()
        if let itemFailureToken {
            NotificationCenter.default.removeObserver(itemFailureToken)
        }
        looper?.disableLooping()
        player.removeAllItems()
    }
}
