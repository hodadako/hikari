import AVFoundation
import LuminaCore
import ScreenSaver

@objc(LuminaScreenSaverView)
final class LuminaScreenSaverView: ScreenSaverView {
    private let playerLayer = AVPlayerLayer()
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.frame = bounds
        layer?.addSublayer(playerLayer)
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func startAnimation() {
        super.startAnimation()
        InterprocessSignal.post(InterprocessSignal.screenSaverDidStart)
        preparePlayer()
    }

    override func stopAnimation() {
        releasePlayer()
        InterprocessSignal.post(InterprocessSignal.screenSaverDidStop)
        super.stopAnimation()
    }

    override func animateOneFrame() {
        // AVPlayerLayer drives frame delivery; ScreenSaverView owns the lifecycle only.
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override var hasConfigureSheet: Bool {
        false
    }

    private func preparePlayer() {
        releasePlayer()
        guard
            let container = try? SharedContainer(
                rootURL: SharedContainer.screenSaverRootURL
            ),
            let content = selectedContent(container: container)
        else {
            return
        }
        let mediaURL = container.mediaURL(for: content)
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            return
        }

        let settings = SettingsStore(container: container).load()
        let item = AVPlayerItem(url: mediaURL)
        item.preferredForwardBufferDuration = VideoRenderer.preferredForwardBufferDuration
        looper = AVPlayerLooper(player: player, templateItem: item)
        playerLayer.videoGravity = settings.scalingMode == .fill
            ? .resizeAspectFill
            : .resizeAspect
        playerLayer.player = player
        // A screen saver is often started while the process is backgrounded.
        // Starting immediately prevents AVFoundation from waiting for the
        // regular application activation cycle before rendering its first
        // frame on the locked display.
        player.playImmediately(atRate: 1)
    }

    private func selectedContent(container: SharedContainer) -> LiveContent? {
        let settings = SettingsStore(container: container).load()
        guard let selectedID = settings.selectedContentID else { return nil }
        return ContentStore(container: container)
            .load()
            .first { $0.id == selectedID }
    }

    private func releasePlayer() {
        player.pause()
        playerLayer.player = nil
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
    }

    deinit {
        releasePlayer()
    }
}
