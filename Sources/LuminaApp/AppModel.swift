import AppKit
import Combine
import CoreServices
import LuminaCore
import ServiceManagement
#if LUMINA_NATIVE_LOCAL
import LuminaNativeLock
#endif

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
    @Published private(set) var isAccessibilityPermissionGranted = false
    @Published private(set) var isInputMonitoringPermissionGranted = false
    #if LUMINA_NATIVE_LOCAL
    @Published private(set) var nativeLockRecord: NativeLockTransactionRecord? = nil
    @Published private(set) var isNativeLockWorking = false
    #endif
    @Published var isShortcutPermissionRecoveryPresented = false
    @Published var presentedError: String?

    let variant = AppVariant.current
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
    #if LUMINA_NATIVE_LOCAL
    private lazy var nativeLockController = NativeLockController(container: container)
    #endif
    private var terminationToken: NSObjectProtocol?
    private var screenSaverSyncTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private var normalizedMenuBarIconCache: [String: NSImage] = [:]
    private var normalizedMenuBarHeartbeatCache: NSImage?
    private let didChangeAppVersion: Bool

    private static let lastLaunchedVersionKey = "lastLaunchedAppVersion"

    init() {
        let currentVersion = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
        let previousVersion = UserDefaults.standard.string(
            forKey: Self.lastLaunchedVersionKey
        )
        didChangeAppVersion = previousVersion != nil
            && previousVersion != currentVersion
        UserDefaults.standard.set(
            currentVersion,
            forKey: Self.lastLaunchedVersionKey
        )

        do {
            let container = try SharedContainer(
                applicationSupportDirectoryName: variant.applicationSupportDirectoryName
            )
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
        if variant.isNativeLocal {
            settings.overrideSystemLockShortcut = false
            settings.lockScreenPlaybackEnabled = false
        } else {
            settings.lastKnownScreenSaverInstalled = screenSaverInstaller.isInstalled
        }
        #if LUMINA_NATIVE_LOCAL
        nativeLockRecord = nativeLockController.currentRecord()
        #endif
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        try? settingsStore.save(settings)
        applyApplicationIcon()
        wallpaperController.setScalingMode(settings.scalingMode)
        reconcilePlayback()
        if variant.supportsScreenSaver, screenSaverInstaller.isInstalled {
            synchronizeScreenSaverContent()
        }
        if variant.supportsScreenSaver {
            lockShortcutController.onShortcut = { [weak self] in
                Task { @MainActor in
                    self?.lockWithLumina()
                }
            }
            refreshLockShortcutIfNeeded(showRecoveryIfUnavailable: true)
        }
        terminationToken = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.shutdown()
            }
        }
        if variant.supportsAutomaticUpdates {
            checkForUpdates()
        }
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
        variant.supportsScreenSaver && screenSaverInstaller.isInstalled
    }

    var isScreenSaverSelected: Bool {
        variant.supportsScreenSaver && screenSaverInstaller.isSelected
    }

    var screenSaverStartDelay: Int {
        variant.supportsScreenSaver ? screenSaverInstaller.startDelay : 0
    }

    var isLockScreenPlaybackEnabled: Bool {
        variant.supportsScreenSaver && settings.lockScreenPlaybackEnabled
    }

    var isScreenSaverUpdateAvailable: Bool {
        variant.supportsScreenSaver && screenSaverInstaller.needsUpdate
    }

    var appDisplayName: String { variant.displayName }

    var isNativeLocalBuild: Bool { variant.isNativeLocal }

    var supportsScreenSaver: Bool { variant.supportsScreenSaver }

    var supportsAutomaticUpdates: Bool { variant.supportsAutomaticUpdates }

    var managedMediaDirectoryDisplayPath: String {
        "~/Library/Application Support/\(variant.applicationSupportDirectoryName)/Media"
    }

    #if LUMINA_NATIVE_LOCAL
    var nativeLockPhase: NativeLockTransactionPhase? {
        nativeLockRecord?.journal.phase
    }

    var nativeLockAppliedContentTitle: String? {
        guard let sourceID = nativeLockRecord?.request.sourceContentID else {
            return nil
        }
        return contents.first { $0.id == sourceID }?.title
            ?? nativeLockRecord?.request.title
    }

    func applySelectedVideoToNativeLock() {
        guard !isNativeLockWorking, let content = selectedContent else { return }
        isNativeLockWorking = true
        Task { [weak self] in
            guard let self else { return }
            do {
                self.nativeLockRecord = try await self.nativeLockController.apply(
                    content: content
                )
            } catch {
                self.nativeLockRecord = self.nativeLockController.currentRecord()
                self.presentedError = error.localizedDescription
            }
            self.isNativeLockWorking = false
            self.objectWillChange.send()
        }
    }

    func restoreNativeLock() {
        guard !isNativeLockWorking else { return }
        isNativeLockWorking = true
        do {
            try nativeLockController.restore()
            nativeLockRecord = nativeLockController.currentRecord()
        } catch {
            nativeLockRecord = nativeLockController.currentRecord()
            presentedError = error.localizedDescription
        }
        isNativeLockWorking = false
        objectWillChange.send()
    }
    #endif

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
        settings.menuBarIconStyle == .lumina && isPlaying
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

    var shortcutPermissionRecoveryMessage: String {
        let key = didChangeAppVersion
            ? "Lumina was updated, and macOS may require you to approve its shortcut permissions again. Allow both Accessibility and Input Monitoring, then return to Lumina and recheck permissions."
            : "Lumina cannot activate its shortcut. Allow both Accessibility and Input Monitoring, then return to Lumina and recheck permissions."
        return NSLocalizedString(key, comment: "Shortcut permission recovery guidance")
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
        guard variant.supportsAutomaticUpdates else { return }
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
        guard variant.supportsAutomaticUpdates else { return }
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
        guard variant.supportsScreenSaver else { return }
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
        guard variant.supportsScreenSaver else { return }
        screenSaverInstaller.openSystemSettings()
    }

    func openLockScreenSettings() {
        guard variant.supportsScreenSaver else { return }
        screenSaverInstaller.openLockScreenSettings()
    }

    func setLockScreenPlayback(_ enabled: Bool) {
        guard variant.supportsScreenSaver else { return }
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
        guard variant.supportsScreenSaver else { return }
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
                "Import a video before using Lumina Lock.",
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
        guard variant.supportsScreenSaver else {
            lockShortcutController.stop()
            return
        }
        if enabled {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Use ^ + Command + Q for Lumina Lock?",
                comment: "Lock shortcut override confirmation title"
            )
            alert.informativeText = NSLocalizedString(
                "Lumina will replace the standard Mac lock shortcut (^ + Command + Q) while it is running. Accessibility and Input Monitoring permission are required. If Lumina is not running, the standard shortcut works normally.",
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
            requestShortcutPermissions()
        } else {
            lockShortcutController.stop()
            refreshShortcutPermissionState()
            isShortcutPermissionRecoveryPresented = false
        }
        objectWillChange.send()
    }

    func requestShortcutPermissions() {
        guard variant.supportsScreenSaver else { return }
        guard settings.overrideSystemLockShortcut else { return }
        if !LockShortcutController.isAccessibilityTrusted {
            _ = LockShortcutController.requestAccessibilityPermission()
        }
        if !LockShortcutController.isInputMonitoringTrusted {
            _ = LockShortcutController.requestInputMonitoringPermission()
        }
        recheckShortcutPermissions()
    }

    func recheckShortcutPermissions() {
        guard variant.supportsScreenSaver else { return }
        lockShortcutController.stop()
        refreshLockShortcutIfNeeded(showRecoveryIfUnavailable: true)
    }

    func openAccessibilitySettings() {
        openPrivacySettings(pane: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(pane: "Privacy_ListenEvent")
    }

    func dismissShortcutPermissionRecovery() {
        isShortcutPermissionRecoveryPresented = false
    }

    func previewScreenSaver() {
        guard variant.supportsScreenSaver else { return }
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
        guard variant.supportsScreenSaver else { return }
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

    private func refreshLockShortcutIfNeeded(
        showRecoveryIfUnavailable: Bool = false
    ) {
        guard variant.supportsScreenSaver else {
            lockShortcutController.stop()
            isAccessibilityPermissionGranted = false
            isInputMonitoringPermissionGranted = false
            isShortcutPermissionRecoveryPresented = false
            return
        }
        guard settings.overrideSystemLockShortcut else {
            lockShortcutController.stop()
            refreshShortcutPermissionState()
            isShortcutPermissionRecoveryPresented = false
            return
        }
        if LockShortcutController.isAccessibilityTrusted {
            _ = lockShortcutController.start()
        }
        refreshShortcutPermissionState()
        if lockShortcutController.isActive {
            isShortcutPermissionRecoveryPresented = false
        } else if showRecoveryIfUnavailable {
            isShortcutPermissionRecoveryPresented = true
        }
        objectWillChange.send()
    }

    private func refreshShortcutPermissionState() {
        isAccessibilityPermissionGranted = LockShortcutController.isAccessibilityTrusted
        // The preflight value can lag behind System Settings. A successfully
        // created event tap is the authoritative proof that current access is
        // sufficient, so do not show a false failure while the tap is active.
        isInputMonitoringPermissionGranted = LockShortcutController.isInputMonitoringTrusted
            || lockShortcutController.isActive
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
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
