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
    private let lockShortcutController = LockShortcutController()
    private lazy var customAppIconStore = CustomAppIconStore(container: container)
    private lazy var screenSaverContentSynchronizer: ScreenSaverContentSynchronizer? = {
        guard let destination = try? SharedContainer(
            rootURL: screenSaverInstaller.contentContainerURL
        ) else {
            return nil
        }
        return ScreenSaverContentSynchronizer(
            sourceContainer: container,
            destinationContainer: destination
        )
    }()
    private lazy var wallpaperController = WallpaperController(renderer: renderer)
    private lazy var systemWallpaperSynchronizer = SystemWallpaperSynchronizer(
        container: container
    )
    private var terminationToken: NSObjectProtocol?
    private var screenSaverSyncTask: Task<Void, Never>?

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
            self?.refreshLockShortcutIfNeeded()
        }
        stateMonitor.onDisplaysChanged = { [weak self] in
            guard let self else { return }
            self.wallpaperController.rebuildWindowsIfContentAvailable(
                self.hasPlayableContent
            )
            self.synchronizeSystemWallpaper(force: true)
        }
        stateMonitor.onActiveSpaceChanged = { [weak self] in
            guard let self else { return }
            self.wallpaperController.refreshWindowsForActiveSpaceIfContentAvailable(
                self.hasPlayableContent
            )
            self.synchronizeSystemWallpaper(force: true)
        }
        stateMonitor.start()
        do {
            try screenSaverInstaller.updateIfNeeded()
        } catch {
            presentedError = String(
                format: NSLocalizedString(
                    "The Lumina screen saver could not be updated: %@",
                    comment: "Screen saver automatic update error"
                ),
                error.localizedDescription
            )
        }
        settings.lastKnownScreenSaverInstalled = screenSaverInstaller.isInstalled
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        try? settingsStore.save(settings)
        applyApplicationIcon()
        wallpaperController.setScalingMode(settings.scalingMode)
        reconcilePlayback()
        synchronizeScreenSaverContent()
        lockShortcutController.onShortcut = { [weak self] in
            Task { @MainActor in
                self?.lockWithLumina()
            }
        }
        refreshLockShortcutIfNeeded()
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

    var isScreenSaverSelected: Bool {
        screenSaverInstaller.isSelected
    }

    var screenSaverStartDelay: Int {
        screenSaverInstaller.startDelay
    }

    var isLockScreenPlaybackEnabled: Bool {
        screenSaverInstaller.isLockScreenPlaybackEnabled
    }

    var appIconImage: NSImage {
        appIconImage(for: settings.appIconStyle)
            ?? NSImage(named: "LuminaIconBlue")
            ?? NSApplication.shared.applicationIconImage
    }

    var isLockShortcutOverrideActive: Bool {
        lockShortcutController.isActive
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
            synchronizeScreenSaverContent()
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
            synchronizeScreenSaverContent()
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

    func setAppIconStyle(_ style: AppIconStyle) {
        guard style != .custom || customAppIconStore.image(
            relativePath: settings.customAppIconRelativePath
        ) != nil else {
            return
        }
        settings.appIconStyle = style
        applyApplicationIcon()
        do {
            try persistSettings()
        } catch {
            presentedError = error.localizedDescription
        }
        objectWillChange.send()
    }

    func importCustomAppIcon(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            settings.customAppIconRelativePath = try customAppIconStore.importIcon(
                from: url
            )
            settings.appIconStyle = .custom
            try persistSettings()
            applyApplicationIcon()
            objectWillChange.send()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func appIconImage(for style: AppIconStyle) -> NSImage? {
        if style == .custom {
            return customAppIconStore.image(
                relativePath: settings.customAppIconRelativePath
            )
        }
        guard let assetName = style.assetName else { return nil }
        return NSImage(named: assetName)
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
            presentedError = String(
                format: NSLocalizedString(
                    "Login item could not be updated: %@",
                    comment: "Login item update error"
                ),
                error.localizedDescription
            )
        }
    }

    func installScreenSaver() {
        do {
            try screenSaverInstaller.install()
            settings.lastKnownScreenSaverInstalled = true
            try persistSettings()
            synchronizeScreenSaverContent(force: true)
            objectWillChange.send()
            screenSaverInstaller.openSystemSettings()
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func openScreenSaverSettings() {
        screenSaverInstaller.openSystemSettings()
    }

    func openLockScreenSettings() {
        screenSaverInstaller.openLockScreenSettings()
    }

    func setLockScreenPlayback(_ enabled: Bool) {
        if enabled {
            guard isScreenSaverInstalled, isScreenSaverSelected else {
                presentedError = NSLocalizedString(
                    "Install and select Lumina as your screen saver first.",
                    comment: "Lock Screen playback requires Lumina screen saver"
                )
                screenSaverInstaller.openSystemSettings()
                return
            }
        }

        if enabled {
            synchronizeScreenSaverContent(force: true)
        }

        guard screenSaverInstaller.setLockScreenPlaybackEnabled(enabled) else {
            presentedError = NSLocalizedString(
                "The Lock Screen playback setting could not be updated.",
                comment: "Lock Screen playback preference update error"
            )
            return
        }
        objectWillChange.send()
    }

    func lockWithLumina() {
        guard isScreenSaverInstalled, isScreenSaverSelected else {
            presentedError = NSLocalizedString(
                "Install and select Lumina as your screen saver first.",
                comment: "Lumina Lock requires the screen saver"
            )
            screenSaverInstaller.openSystemSettings()
            return
        }
        guard selectedContent != nil else {
            presentedError = NSLocalizedString(
                "Import an MP4 before using Lumina Lock.",
                comment: "Lumina Lock requires content"
            )
            return
        }
        guard let synchronizer = screenSaverContentSynchronizer else {
            presentedError = NSLocalizedString(
                "The Lock Screen video storage could not be prepared.",
                comment: "Screen saver content container preparation error"
            )
            return
        }
        let content = selectedContent
        let settings = settings
        screenSaverSyncTask?.cancel()
        screenSaverSyncTask = Task { [weak self] in
            do {
                try await synchronizer.synchronize(
                    content: content,
                    settings: settings,
                    force: true
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.presentedError = String(
                    format: NSLocalizedString(
                        "The Lock Screen video could not be synchronized: %@",
                        comment: "Screen saver content synchronization error"
                    ),
                    error.localizedDescription
                )
                return
            }
            guard let self, self.screenSaverInstaller.startPreview() else {
                self?.presentedError = NSLocalizedString(
                    "Lumina Lock could not start the screen saver.",
                    comment: "Lumina Lock launch error"
                )
                return
            }
        }
    }

    func setLockShortcutOverride(_ enabled: Bool) {
        if enabled {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Use ^ + Command + Q for Lumina Lock?",
                comment: "Lock shortcut override confirmation title"
            )
            alert.informativeText = NSLocalizedString(
                "Lumina will replace the standard Mac lock shortcut (^ + Command + Q) while it is running. Accessibility permission is required. If Lumina is not running, the standard shortcut works normally.",
                comment: "Lock shortcut override confirmation message"
            )
            alert.addButton(withTitle: NSLocalizedString("Enable", comment: "Enable action"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel action"))
            guard alert.runModal() == .alertFirstButtonReturn else {
                objectWillChange.send()
                return
            }
        }

        settings.overrideSystemLockShortcut = enabled
        do {
            try persistSettings()
        } catch {
            presentedError = error.localizedDescription
        }

        if enabled {
            let trusted = LockShortcutController.isAccessibilityTrusted
                || LockShortcutController.requestAccessibilityPermission()
            if trusted {
                refreshLockShortcutIfNeeded()
            } else {
                presentedError = NSLocalizedString(
                    "Allow Lumina in Privacy & Security > Accessibility, then return to Lumina. The shortcut will activate automatically.",
                    comment: "Accessibility permission instructions"
                )
            }
        } else {
            lockShortcutController.stop()
        }
        objectWillChange.send()
    }

    func previewScreenSaver() {
        guard isScreenSaverInstalled, isScreenSaverSelected else {
            presentedError = NSLocalizedString(
                "Select Lumina as your screen saver in System Settings first.",
                comment: "Screen saver preview requires selection"
            )
            screenSaverInstaller.openSystemSettings()
            return
        }
        guard screenSaverInstaller.startPreview() else {
            presentedError = NSLocalizedString(
                "The Lumina screen saver preview could not be opened.",
                comment: "Screen saver preview launch error"
            )
            return
        }
    }

    func thumbnailURL(for content: LiveContent) -> URL? {
        container.thumbnailURL(for: content)
    }

    func shutdown() {
        stateMonitor.stop()
        lockShortcutController.stop()
        systemWallpaperSynchronizer.cancelPendingWork()
        screenSaverSyncTask?.cancel()
        renderer.stopAndRelease()
        wallpaperController.closeWindows()
    }

    deinit {
        if let terminationToken {
            NotificationCenter.default.removeObserver(terminationToken)
        }
    }

    private func reconcilePlayback() {
        let mediaURL = selectedMediaURL
        let hasContent = hasPlayableContent

        wallpaperController.setContentAvailable(hasContent)
        synchronizeSystemWallpaper()

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

    private func synchronizeScreenSaverContent(force: Bool = false) {
        guard let synchronizer = screenSaverContentSynchronizer else {
            presentedError = NSLocalizedString(
                "The Lock Screen video storage could not be prepared.",
                comment: "Screen saver content container preparation error"
            )
            return
        }
        let content = selectedContent
        let settings = settings
        screenSaverSyncTask?.cancel()
        screenSaverSyncTask = Task { [weak self] in
            do {
                try await synchronizer.synchronize(
                    content: content,
                    settings: settings,
                    force: force
                )
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.presentedError = String(
                    format: NSLocalizedString(
                        "The Lock Screen video could not be synchronized: %@",
                        comment: "Screen saver content synchronization error"
                    ),
                    error.localizedDescription
                )
            }
        }
    }

    private func refreshLockShortcutIfNeeded() {
        guard settings.overrideSystemLockShortcut else {
            lockShortcutController.stop()
            return
        }
        if LockShortcutController.isAccessibilityTrusted {
            _ = lockShortcutController.start()
        }
        objectWillChange.send()
    }

    private func synchronizeSystemWallpaper(force: Bool = false) {
        systemWallpaperSynchronizer.synchronize(
            content: selectedContent,
            mediaURL: selectedMediaURL,
            thumbnailURL: selectedContent.flatMap(container.thumbnailURL(for:)),
            scalingMode: settings.scalingMode,
            force: force
        ) { [weak self] error in
            self?.presentedError = String(
                format: NSLocalizedString(
                    "The menu bar background could not be updated: %@",
                    comment: "System wallpaper synchronization error"
                ),
                error.localizedDescription
            )
        }
    }

    private var hasPlayableContent: Bool {
        guard let mediaURL = selectedMediaURL else { return false }
        return FileManager.default.fileExists(atPath: mediaURL.path)
    }

    private func saveAndReconcile() {
        do {
            try persistSettings()
        } catch {
            presentedError = error.localizedDescription
        }
        reconcilePlayback()
        synchronizeScreenSaverContent()
    }

    private func persistSettings() throws {
        try settingsStore.save(settings)
    }

    private func applyApplicationIcon() {
        NSApplication.shared.applicationIconImage = appIconImage
    }
}
