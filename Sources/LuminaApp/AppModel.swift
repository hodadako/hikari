import AppKit
import Combine
import LuminaCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var contents: [LiveContent]
    @Published private(set) var settings: LuminaSettings
    @Published private(set) var pauseReasons: Set<PlaybackPauseReason> = []
    @Published private(set) var isImporting = false
    @Published var presentedError: String?

    let container: SharedContainer

    private let settingsStore: SettingsStore
    private let contentStore: ContentStore
    private let importer: VideoImporter
    private let renderer = VideoRenderer()
    private let stateMonitor = SystemStateMonitor()
    private let screenSaverInstaller = ScreenSaverInstaller()
    private lazy var wallpaperController = WallpaperController(renderer: renderer)
    private var terminationToken: NSObjectProtocol?

    init() {
        do {
            let container = try SharedContainer()
            self.container = container
            self.settingsStore = SettingsStore(container: container)
            self.contentStore = ContentStore(container: container)
            self.importer = VideoImporter(container: container)
            self.contents = contentStore.load()
            self.settings = settingsStore.load()
        } catch {
            fatalError("Lumina could not prepare its storage: \(error.localizedDescription)")
        }

        stateMonitor.onStateChanged = { [weak self] in
            self?.reconcilePlayback()
        }
        stateMonitor.onDisplaysChanged = { [weak self] in
            self?.wallpaperController.rebuildWindows()
        }
        stateMonitor.start()
        settings.lastKnownScreenSaverInstalled = screenSaverInstaller.isInstalled
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        try? settingsStore.save(settings)
        wallpaperController.setScalingMode(settings.scalingMode)
        wallpaperController.rebuildWindows()
        reconcilePlayback()
        terminationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.shutdown()
            }
        }
    }

    var selectedContent: LiveContent? {
        contents.first { $0.id == settings.selectedContentID }
    }

    var selectedMediaURL: URL? {
        selectedContent.map(container.mediaURL(for:))
    }

    var isPlaying: Bool {
        renderer.isPlaying
    }

    var isScreenSaverInstalled: Bool {
        screenSaverInstaller.isInstalled
    }

    func importVideo(from url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let content = try await importer.importVideo(
                from: url,
                existingContents: contents
            )
            contents.append(content)
            try contentStore.save(contents)
            settings.selectedContentID = content.id
            settings.playbackPreference = .playing
            try persistSettings()
            reconcilePlayback()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func select(_ content: LiveContent) {
        settings.selectedContentID = content.id
        settings.playbackPreference = .playing
        saveAndReconcile()
    }

    func delete(_ content: LiveContent) {
        do {
            contents = try contentStore.delete(content, from: contents)
            if settings.selectedContentID == content.id {
                settings.selectedContentID = contents.first?.id
            }
            try persistSettings()
            reconcilePlayback()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func togglePlayback() {
        settings.playbackPreference = settings.playbackPreference == .playing
            ? .paused
            : .playing
        saveAndReconcile()
    }

    func setScalingMode(_ mode: ScalingMode) {
        settings.scalingMode = mode
        wallpaperController.setScalingMode(mode)
        saveAndReconcile()
    }

    func setMuted(_ muted: Bool) {
        settings.isMuted = muted
        renderer.setMuted(muted)
        saveAndReconcile()
    }

    func setPauseOnBattery(_ enabled: Bool) {
        settings.pauseOnBattery = enabled
        saveAndReconcile()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            settings.launchAtLogin = enabled
            try persistSettings()
        } catch {
            presentedError = "Login item could not be updated: \(error.localizedDescription)"
        }
    }

    func installScreenSaver() {
        do {
            try screenSaverInstaller.install()
            settings.lastKnownScreenSaverInstalled = true
            try persistSettings()
            objectWillChange.send()
            screenSaverInstaller.openSystemSettings()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func openScreenSaverSettings() {
        screenSaverInstaller.openSystemSettings()
    }

    func thumbnailURL(for content: LiveContent) -> URL? {
        container.thumbnailURL(for: content)
    }

    func shutdown() {
        stateMonitor.stop()
        renderer.stopAndRelease()
        wallpaperController.closeWindows()
    }

    deinit {
        if let terminationToken {
            NotificationCenter.default.removeObserver(terminationToken)
        }
    }

    private func reconcilePlayback() {
        let content = selectedContent
        let mediaURL = content.map(container.mediaURL(for:))
        let hasContent = mediaURL.map {
            FileManager.default.fileExists(atPath: $0.path)
        } ?? false

        if let mediaURL, hasContent {
            renderer.load(url: mediaURL, muted: settings.isMuted)
        } else {
            renderer.stopAndRelease()
        }

        let policy = PlaybackPolicy(
            userWantsPlayback: settings.playbackPreference == .playing,
            pauseOnBattery: settings.pauseOnBattery,
            isOnBattery: stateMonitor.isOnBattery,
            isScreenLocked: stateMonitor.isScreenLocked,
            isScreenSaverRunning: stateMonitor.isScreenSaverRunning,
            isSleeping: stateMonitor.isSleeping,
            hasContent: hasContent
        )
        pauseReasons = policy.pauseReasons
        if policy.shouldPlay {
            renderer.play()
        } else {
            renderer.pause()
        }
        objectWillChange.send()
    }

    private func saveAndReconcile() {
        do {
            try persistSettings()
        } catch {
            presentedError = error.localizedDescription
        }
        reconcilePlayback()
    }

    private func persistSettings() throws {
        try settingsStore.save(settings)
    }
}
