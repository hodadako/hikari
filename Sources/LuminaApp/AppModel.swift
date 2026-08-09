import AppKit
import Combine
import CoreServices
import LuminaCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var contents: [LiveContent]
    @Published private(set) var settings: LuminaSettings
    @Published private(set) var pauseReasons: Set<PlaybackPauseReason> = []
    @Published private(set) var isImporting = false
    @Published private(set) var latestRelease: LatestRelease?
    @Published private(set) var updateCheckState: UpdateCheckState = .idle
    @Published private(set) var isApplyingUpdate = false
    @Published private(set) var updateErrorMessage: String?
    @Published var presentedError: String?

    let container: SharedContainer

    private let settingsStore: SettingsStore
    private let contentStore: ContentStore
    private let importer: VideoImporter
    private let stateMonitor = SystemStateMonitor()
    private let screenSaverInstaller = ScreenSaverInstaller()
    private let lockShortcutController = LockShortcutController()
    private lazy var customAppIconStore = CustomAppIconStore(container: container)
    private lazy var customMenuBarIconStore = CustomMenuBarIconStore(container: container)
    private let releaseUpdateService = ReleaseUpdateService()
    private lazy var appUpdateInstaller = AppUpdateInstaller()
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
    private lazy var wallpaperController = WallpaperController()
    private var terminationToken: NSObjectProtocol?
    private var screenSaverSyncTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var normalizedMenuBarIconCache: [String: NSImage] = [:]
    private var normalizedMenuBarHeartbeatCache: NSImage?

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
            guard let self else { return }
            self.reconcilePlayback()
            self.refreshLockShortcutIfNeeded()
        }
        stateMonitor.onDisplaysChanged = { [weak self] in
            guard let self else { return }
            self.wallpaperController.rebuildWindowsIfContentAvailable(
                self.hasPlayableContent
            )
        }
        stateMonitor.onActiveSpaceChanged = { [weak self] in
            guard let self else { return }
            self.wallpaperController.refreshWindowsForActiveSpaceIfContentAvailable(
                self.hasPlayableContent
            )
            self.reconcilePlayback()
        }
        stateMonitor.start()
        settings.lastKnownScreenSaverInstalled = screenSaverInstaller.isInstalled
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        try? settingsStore.save(settings)
        applyApplicationIcon()
        wallpaperController.setScalingMode(settings.scalingMode)
        reconcilePlayback()
        if screenSaverInstaller.isInstalled {
            synchronizeScreenSaverContent()
        }
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
        checkForUpdates()
    }

    var selectedContent: LiveContent? {
        contents.first { $0.id == settings.selectedContentID }
    }

    var selectedMediaURL: URL? {
        selectedContent.map(container.mediaURL(for:))
    }

    var isPlaying: Bool {
        wallpaperController.isPlaying
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
        settings.lockScreenPlaybackEnabled
    }

    var isScreenSaverUpdateAvailable: Bool {
        screenSaverInstaller.needsUpdate
    }

    var appIconImage: NSImage {
        appIconImage(for: settings.appIconStyle)
            ?? NSImage(named: "LuminaIconDefault")
            ?? NSApplication.shared.applicationIconImage
    }

    var menuBarIconImage: NSImage {
        menuBarIconImage(for: settings.menuBarIconStyle)
            ?? NSImage(named: "MenuBarIconLumina")
            ?? NSImage(systemSymbolName: "sparkles.tv", accessibilityDescription: "Lumina")
            ?? NSImage()
    }

    var menuBarHeartbeatImage: NSImage? {
        guard settings.menuBarIconStyle == .lumina else { return nil }
        if let normalizedMenuBarHeartbeatCache {
            return normalizedMenuBarHeartbeatCache
        }
        guard let baseImage = NSImage(named: "MenuBarIconLumina"),
              let heartbeatImage = NSImage(named: "MenuBarIconHeartbeat") else {
            return nil
        }
        let normalizedImage = MenuBarIconRenderer.normalizedImage(
            from: heartbeatImage,
            framedBy: baseImage
        )
        normalizedImage.isTemplate = false
        normalizedMenuBarHeartbeatCache = normalizedImage
        return normalizedImage
    }

    var shouldPulseMenuBarSparkle: Bool {
        settings.menuBarIconStyle == .lumina
    }

    var menuBarIconIsTemplate: Bool {
        settings.menuBarIconStyle.isTemplate
    }

    var currentAppVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
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

    func setMenuBarIconStyle(_ style: MenuBarIconStyle) {
        guard style != .custom || customMenuBarIconStore.image(
            relativePath: settings.customMenuBarIconRelativePath
        ) != nil else {
            return
        }
        settings.menuBarIconStyle = style
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

    func importCustomMenuBarIcon(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        do {
            settings.customMenuBarIconRelativePath = try customMenuBarIconStore.importIcon(
                from: url
            )
            settings.menuBarIconStyle = .custom
            normalizedMenuBarIconCache.removeAll()
            try persistSettings()
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

    func menuBarIconImage(for style: MenuBarIconStyle) -> NSImage? {
        let cacheKey = style == .custom
            ? "custom:\(settings.customMenuBarIconRelativePath ?? "")"
            : style.rawValue
        if let cachedImage = normalizedMenuBarIconCache[cacheKey] {
            return cachedImage
        }

        let sourceImage: NSImage?
        if style == .custom {
            sourceImage = customMenuBarIconStore.image(
                relativePath: settings.customMenuBarIconRelativePath
            )
        } else if let assetName = style.assetName {
            sourceImage = NSImage(named: assetName)
        } else {
            sourceImage = nil
        }
        guard let sourceImage else { return nil }

        let normalizedImage = MenuBarIconRenderer.normalizedImage(from: sourceImage)
        normalizedImage.isTemplate = style.isTemplate
        normalizedMenuBarIconCache[cacheKey] = normalizedImage
        return normalizedImage
    }

    func checkForUpdates() {
        guard updateCheckState != .checking else { return }
        updateTask?.cancel()
        updateCheckState = .checking
        latestRelease = nil
        updateErrorMessage = nil
        updateTask = Task { [weak self] in
            do {
                let release = try await self?.releaseUpdateService.fetchLatestRelease()
                guard let self, let release, !Task.isCancelled else { return }
                guard let latestVersion = release.version,
                      let currentVersion = LuminaVersion(self.currentAppVersion) else {
                    self.latestRelease = nil
                    self.updateCheckState = .failed
                    self.updateErrorMessage = ReleaseUpdateError.invalidReleaseVersion.localizedDescription
                    return
                }
                self.latestRelease = release
                self.updateCheckState = latestVersion > currentVersion
                    ? .updateAvailable
                    : .upToDate
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.latestRelease = nil
                self.updateCheckState = .failed
                self.updateErrorMessage = error.localizedDescription
            }
        }
    }

    func applyLatestUpdate() {
        guard !isApplyingUpdate else { return }
        guard let release = latestRelease,
              updateCheckState == .updateAvailable else {
            checkForUpdates()
            return
        }
        isApplyingUpdate = true
        let installer = appUpdateInstaller
        updateTask?.cancel()
        updateTask = Task { [weak self, installer] in
            do {
                try await installer.install(release)
            } catch is CancellationError {
                guard let self else { return }
                self.isApplyingUpdate = false
            } catch {
                guard let self else { return }
                self.isApplyingUpdate = false
                self.presentedError = error.localizedDescription
            }
        }
    }

    func setMuted(_ muted: Bool) {
        settings.isMuted = muted
        wallpaperController.setMuted(muted)
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

        var nextSettings = settings
        if enabled {
            var policy = ScreenSaverIdleTimePolicy(
                originalIdleTime: settings.screenSaverPreviousIdleTime
            )
            _ = policy.enable(currentIdleTime: screenSaverInstaller.startDelay)
            nextSettings.screenSaverPreviousIdleTime = policy.originalIdleTime
            nextSettings.lockScreenPlaybackEnabled = true
        } else {
            var policy = ScreenSaverIdleTimePolicy(
                originalIdleTime: settings.screenSaverPreviousIdleTime
            )
            _ = policy.disable(fallbackIdleTime: screenSaverInstaller.startDelay)
            nextSettings.screenSaverPreviousIdleTime = nil
            nextSettings.lockScreenPlaybackEnabled = false
        }

        let targetIdleTime: Int
        let currentIdleTime = screenSaverInstaller.startDelay
        if enabled {
            targetIdleTime = 60
        } else {
            targetIdleTime = settings.screenSaverPreviousIdleTime
                ?? currentIdleTime
        }

        let previousSettings = settings
        guard screenSaverInstaller.setIdleTime(targetIdleTime) else {
            presentedError = NSLocalizedString(
                "The Lock Screen playback setting could not be updated.",
                comment: "Lock Screen playback preference update error"
            )
            return
        }
        settings = nextSettings
        do {
            try persistSettings()
        } catch {
            settings = previousSettings
            _ = screenSaverInstaller.setIdleTime(
                previousSettings.lockScreenPlaybackEnabled
                    ? 60
                    : currentIdleTime
            )
            presentedError = error.localizedDescription
            objectWillChange.send()
            return
        }
        if enabled {
            synchronizeScreenSaverContent(force: true)
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
                    force: false
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
        screenSaverSyncTask?.cancel()
        updateTask?.cancel()
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
        let playableURL = hasContent ? mediaURL : nil

        wallpaperController.setContentAvailable(hasContent)

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
            wallpaperController.setContent(url: playableURL, muted: settings.isMuted)
            wallpaperController.play()
        } else {
            wallpaperController.setContent(url: playableURL, muted: settings.isMuted)
            wallpaperController.pause()
        }
        objectWillChange.send()
    }

    private func synchronizeScreenSaverContent(force: Bool = false) {
        // Merely launching Lumina must not create or modify screen saver
        // support data. Content is synchronized only after the user has
        // explicitly installed Lumina (or invokes a screen-saver action).
        guard screenSaverInstaller.isInstalled else { return }
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
        let image = appIconImage
        let appURL = Bundle.main.bundleURL
        let appPath = appURL.path
        image.isTemplate = false
        NSApplication.shared.applicationIconImage = image

        let finderIcon = settings.appIconStyle == .custom ? image : nil
        guard NSWorkspace.shared.setIcon(
            finderIcon,
            forFile: appPath,
            options: []
        ) else {
            presentedError = NSLocalizedString(
                "The Finder icon could not be updated.",
                comment: "Finder app icon update failure"
            )
            return
        }

        // Finder keeps a separate icon cache from Launch Services. The default
        // style clears any custom Finder override so AppIcon.icns remains the
        // canonical icon; the custom style writes its imported image instead.
        NSWorkspace.shared.noteFileSystemChanged(appPath)
        NSWorkspace.shared.noteFileSystemChanged(
            appURL.deletingLastPathComponent().path
        )
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.FinderInfoChanged"),
            object: appPath,
            userInfo: nil
        )
        LSRegisterURL(appURL as CFURL, true)
    }
}
