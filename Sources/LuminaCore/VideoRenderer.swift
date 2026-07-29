import AVFoundation
import Combine
import Foundation

@MainActor
public final class VideoRenderer: ObservableObject {
    @Published public private(set) var currentURL: URL?
    @Published public private(set) var isPlaying = false

    public let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

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
        looper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = muted
        currentURL = url
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

    public func stopAndRelease() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        currentURL = nil
        isPlaying = false
    }

    deinit {
        player.pause()
        looper?.disableLooping()
        player.removeAllItems()
    }
}
