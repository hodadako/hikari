import AppKit
import Combine
import CoreServices
import Darwin
import LuminaCore
import LuminaNativeLock
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
    @Published private(set) var nativeLockRecord: NativeLockTransactionRecord? = nil
    @Published private(set) var isNativeLockWorking = false
    @Published private(set) var nativeStorageMigrationReport =
        NativeStorageMigrationReport.notNeeded
    @Published private(set) var storageMigrationErrorMessage: String?
    @Published var presentedError: String?

    let variant = AppVariant.current
    let container: SharedContainer

    private let settingsStore: SettingsStore
    private let contentStore: ContentStore
    private let importer: VideoImporter
    private let stateMonitor = SystemStateMonitor()
    private lazy var customAppIconStore = CustomAppIconStore(container: container)
    private lazy var customMenuBarIconStore = CustomMenuBarIconStore(container: container)
    private let releaseUpdateService = ReleaseUpdateService()
    private lazy var appUpdateInstaller = AppUpdateInstaller()
    private lazy var wallpaperController = WallpaperController()
    private lazy var nativeLockController = NativeLockController(container: container)
    private var nativeLockMaintenanceTask: Task<Void, Never>?
    private var nativeLockAutoApplyTask: Task<Void, Never>?
    private var nativeRendererRefreshTask: Task<Void, Never>?
    private var nativeLockMaintenanceInProgress = false
    private var nativeRendererRefreshRequested = false
    private var didPresentNativeMaintenanceError = false
    private var wasScreenLocked = false
    private var terminationToken: NSObjectProtocol?
    private var updateTask: Task<Void, Never>?
    private var normalizedMenuBarIconCache: [String: NSImage] = [:]
    private var normalizedMenuBarHeartbeatCache: NSImage?
    init() {
        do {
            let canonicalURL = try SharedContainer.applicationSupportRootURL(
                directoryName: variant.applicationSupportDirectoryName
            )
            let legacyURL = canonicalURL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    NativeStorageMigration.legacyDirectoryName,
                    isDirectory: true
                )
            var migrationReport = NativeStorageMigrationReport.notNeeded
            var migrationError: Error?
            do {
                migrationReport = try NativeStorageMigration.migrate(
                    canonicalRootURL: canonicalURL,
                    legacyRootURL: legacyURL,
                    userID: UInt32(getuid())
                )
            } catch {
                // Keep the legacy directory untouched on failure. Hikari can
                // still open its canonical library, but updates stay blocked
                // until the migration problem is resolved.
                migrationError = error
            }

            let container = try SharedContainer(rootURL: canonicalURL)
            self.container = container
            self.settingsStore = SettingsStore(container: container)
            self.contentStore = ContentStore(container: container)
            self.importer = VideoImporter(container: container)
            self.contents = contentStore.load()
            self.settings = settingsStore.load()
            self.nativeStorageMigrationReport = migrationReport
            self.storageMigrationErrorMessage = migrationError?.localizedDescription
        } catch {
            fatalError(
                "\(variant.displayName) could not prepare its storage: "
                    + error.localizedDescription
            )
        }

        stateMonitor.onStateChanged = { [weak self] in
            guard let self else { return }
            let didUnlock = self.wasScreenLocked && !self.stateMonitor.isScreenLocked
            self.wasScreenLocked = self.stateMonitor.isScreenLocked
            if didUnlock {
                self.requestNativeRendererRefreshAfterUnlock()
            }
            self.reconcilePlayback()
        }
        stateMonitor.onDisplaysChanged = { [weak self] in
            guard let self, self.hasPlayableContent else { return }
            // Early WindowServer snapshots only update display membership and
            // geometry. Recreating every AVPlayer here restarts all displays.
            self.wallpaperController.synchronizeDisplayTopology()
        }
        stateMonitor.onDisplaysSettled = { [weak self] in
            guard let self else { return }
            // The final snapshot confirms the topology, but does not tear
            // down healthy players on displays that were not changed.
            self.wallpaperController.finishDisplayTopologyTransitionIfContentAvailable(
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
        stateMonitor.onActiveSpaceSettled = { [weak self] in
            guard let self else { return }
            // A desktop-level window can remain alive while Mission Control
            // invalidates its AVPlayerLayer presentation surface.  The early
            // Space passes above keep membership current; this final settled
            // pass recreates the surface once, preserving playback state.
            self.wallpaperController.rebuildWindowsIfContentAvailable(
                self.hasPlayableContent
            )
            self.reconcilePlayback()
        }
        stateMonitor.start()
        // These settings belonged to the archived screen-saver/event-tap
        // product. Keep them readable, but never let them affect Hikari.
        settings.overrideSystemLockShortcut = false
        settings.lockScreenPlaybackEnabled = false
        settings.lastKnownScreenSaverInstalled = false
        nativeLockRecord = nativeLockController.currentRecord()
        wasScreenLocked = stateMonitor.isScreenLocked
        startNativeLockMaintenance()
        scheduleNativeLockAutoApply()
        settings.launchAtLogin = SMAppService.mainApp.status == .enabled
        try? settingsStore.save(settings)
        applyApplicationIcon()
        wallpaperController.setScalingMode(settings.scalingMode)
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
        if let storageMigrationErrorMessage {
            presentedError = storageMigrationErrorMessage
        } else if let updateBlockedReason {
            updateErrorMessage = updateBlockedReason
        } else if variant.supportsAutomaticUpdates {
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

    var appDisplayName: String { variant.displayName }

    var attentionTitle: String {
        NSLocalizedString(
            "Hikari Needs Attention",
            comment: "App-specific error alert title"
        )
    }

    var supportsAutomaticUpdates: Bool { variant.supportsAutomaticUpdates }

    var managedMediaDirectoryDisplayPath: String {
        "~/Library/Application Support/\(variant.applicationSupportDirectoryName)/Media"
    }

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

    /// Any unfinished Native Lock transaction may still own macOS wallpaper
    /// state. Updating the app is therefore disabled until Restore completes.
    var updateBlockedReason: String? {
        if let storageMigrationErrorMessage {
            return String(
                format: NSLocalizedString(
                    "Hikari could not finish its storage migration: %@",
                    comment: "Storage migration update block"
                ),
                storageMigrationErrorMessage
            )
        }
        if nativeStorageMigrationReport.requiresRestore,
           nativeLockRecord == nil {
            return NSLocalizedString(
                "Restore the previous Native Lock transaction before updating Hikari.",
                comment: "Legacy Native Lock migration update block"
            )
        }
        guard let phase = nativeLockPhase, phase != .restored else {
            return nil
        }
        return NSLocalizedString(
            "Restore Native Lock before updating Hikari.",
            comment: "Native Lock update block"
        )
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
                self.nativeRendererRefreshTask?.cancel()
                self.nativeRendererRefreshTask = nil
                self.nativeRendererRefreshRequested = false
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
            nativeRendererRefreshTask?.cancel()
            nativeRendererRefreshTask = nil
            nativeRendererRefreshRequested = false
        } catch {
            nativeLockRecord = nativeLockController.currentRecord()
            presentedError = error.localizedDescription
        }
        isNativeLockWorking = false
        objectWillChange.send()
    }

    var canDiscardKnownNoopNativeLockPreflight: Bool {
        guard let nativeLockRecord else { return false }
        return NativeLockRecovery.canDiscardKnownNoopLegacyPreflight(
            nativeLockRecord.journal,
            operatingSystemMajorVersion: ProcessInfo.processInfo
                .operatingSystemVersion.majorVersion
        )
    }

    func discardKnownNoopNativeLockPreflight() {
        guard !isNativeLockWorking else { return }
        isNativeLockWorking = true
        defer { isNativeLockWorking = false }
        do {
            try nativeLockController.discardKnownNoopLegacyPreflight()
            nativeLockRecord = nativeLockController.currentRecord()
            didPresentNativeMaintenanceError = false
        } catch {
            presentedError = error.localizedDescription
        }
        objectWillChange.send()
    }

    var appIconImage: NSImage {
        appIconImage(for: settings.appIconStyle)
            ?? NSImage(named: "LuminaIconDefault")
            ?? NSApplication.shared.applicationIconImage
    }

    var menuBarIconImage: NSImage {
        menuBarIconImage(for: settings.menuBarIconStyle)
            ?? NSImage(named: "MenuBarIconLumina")
            ?? NSImage(
                systemSymbolName: "sparkles.tv",
                accessibilityDescription: variant.displayName
            )
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
            if error as? LuminaError == .duplicateContent {
                presentedError = NSLocalizedString(
                    "This video is already in your Hikari library.",
                    comment: "Native Local duplicate video error"
                )
            } else {
                presentedError = error.localizedDescription
            }
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
        guard updateBlockedReason == nil else {
            updateCheckState = .failed
            updateErrorMessage = updateBlockedReason
            return
        }
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
        guard updateBlockedReason == nil else {
            presentedError = updateBlockedReason
            return
        }
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

    func thumbnailURL(for content: LiveContent) -> URL? {
        container.thumbnailURL(for: content)
    }

    func shutdown() {
        stateMonitor.stop()
        updateTask?.cancel()
        nativeLockMaintenanceTask?.cancel()
        nativeLockMaintenanceTask = nil
        nativeLockAutoApplyTask?.cancel()
        nativeLockAutoApplyTask = nil
        nativeRendererRefreshTask?.cancel()
        nativeRendererRefreshTask = nil
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

    private func scheduleNativeLockAutoApply() {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
              nativeLockRecord?.journal.phase != .active,
              nativeLockRecord?.journal.phase != .recoveryRequired,
              selectedContent != nil,
              nativeLockAutoApplyTask == nil else {
            return
        }
        nativeLockAutoApplyTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            guard !self.stateMonitor.isScreenLocked,
                  !self.stateMonitor.isSleeping,
                  self.nativeLockRecord?.journal.phase != .active,
                  self.nativeLockRecord?.journal.phase != .recoveryRequired,
                  self.selectedContent != nil else {
                return
            }
            self.applySelectedVideoToNativeLock()
        }
    }

    private func startNativeLockMaintenance() {
        guard nativeLockMaintenanceTask == nil else { return }
        nativeRendererRefreshRequested = nativeLockRecord?.journal.phase == .active
        let clock = SuspendingClock()
        nativeLockMaintenanceTask = Task { [weak self] in
            await self?.performNativeLockMaintenance()
            while !Task.isCancelled {
                try? await clock.sleep(
                    until: clock.now.advanced(by: .seconds(5))
                )
                guard !Task.isCancelled else { return }
                await self?.performNativeLockMaintenance()
            }
        }
    }

    private func requestNativeRendererRefreshAfterUnlock() {
        nativeRendererRefreshTask?.cancel()
        nativeRendererRefreshTask = Task { [weak self] in
            // WallpaperAgent owns the outgoing Lock Screen surface briefly
            // after the unlock notification. Restarting it immediately tears
            // down that surface during the transition and visibly flashes the
            // desktop. Wait for the transition to settle, then refresh once
            // while the session is safely unlocked.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.nativeRendererRefreshRequested = true
            await self.performNativeLockMaintenance()
        }
    }

    private func performNativeLockMaintenance() async {
        // Never rewrite choices or restart WallpaperAgent while the Lock
        // Screen owns its presentation surfaces. Unlock schedules an immediate
        // pass after the session has returned to the desktop.
        guard !stateMonitor.isScreenLocked,
              !stateMonitor.isSleeping,
              !nativeLockMaintenanceInProgress,
              !isNativeLockWorking else { return }
        nativeLockMaintenanceInProgress = true
        let shouldRefreshRenderer = nativeRendererRefreshRequested
        nativeRendererRefreshRequested = false
        defer { nativeLockMaintenanceInProgress = false }
        do {
            nativeLockRecord = try await nativeLockController
                .maintainActiveTransaction(
                    refreshRenderer: shouldRefreshRenderer
                )
            didPresentNativeMaintenanceError = false
            objectWillChange.send()
        } catch {
            // Keep a renderer refresh pending after a transient process-control
            // failure. Mapping reconciliation is idempotent and will be retried
            // by the next five-second maintenance tick.
            nativeRendererRefreshRequested = nativeRendererRefreshRequested
                || shouldRefreshRenderer
            nativeLockRecord = nativeLockController.currentRecord()
            if !didPresentNativeMaintenanceError {
                presentedError = error.localizedDescription
                didPresentNativeMaintenanceError = true
            }
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
