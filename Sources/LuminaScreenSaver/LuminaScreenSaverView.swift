import AVFoundation
import LuminaCore
import ScreenSaver

@objc(LuminaScreenSaverView)
final class LuminaScreenSaverView: ScreenSaverView {
    private let playerLayer = AVPlayerLayer()
    private var isAttachedToPlayback = false

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
            let container = try? SharedContainer(),
            let content = selectedContent(container: container)
        else {
            return
        }
        let mediaURL = container.mediaURL(for: content)
        guard FileManager.default.fileExists(atPath: mediaURL.path) else {
            return
        }

        let settings = SettingsStore(container: container).load()
        SharedScreenSaverPlayback.shared.attach(
            layer: playerLayer,
            mediaURL: mediaURL,
            scalingMode: settings.scalingMode
        )
        isAttachedToPlayback = true
    }

    private func selectedContent(container: SharedContainer) -> LiveContent? {
        let settings = SettingsStore(container: container).load()
        guard let selectedID = settings.selectedContentID else { return nil }
        return ContentStore(container: container)
            .load()
            .first { $0.id == selectedID }
    }

    private func releasePlayer() {
        guard isAttachedToPlayback else { return }
        playerLayer.player = nil
        SharedScreenSaverPlayback.shared.detach()
        isAttachedToPlayback = false
    }

    deinit {
        releasePlayer()
    }
}

@MainActor
private final class SharedScreenSaverPlayback {
    static let shared = SharedScreenSaverPlayback()

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private var attachmentCount = 0

    private init() {
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
        player.isMuted = true
    }

    func attach(
        layer: AVPlayerLayer,
        mediaURL: URL,
        scalingMode: ScalingMode
    ) {
        if currentURL != mediaURL {
            releasePlayer()
            let item = AVPlayerItem(url: mediaURL)
            item.preferredForwardBufferDuration = 2
            looper = AVPlayerLooper(player: player, templateItem: item)
            currentURL = mediaURL
        }
        attachmentCount += 1
        layer.videoGravity = scalingMode == .fill
            ? .resizeAspectFill
            : .resizeAspect
        layer.player = player
        player.play()
    }

    func detach() {
        attachmentCount = max(0, attachmentCount - 1)
        if attachmentCount == 0 {
            releasePlayer()
        }
    }

    private func releasePlayer() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        currentURL = nil
    }
}
