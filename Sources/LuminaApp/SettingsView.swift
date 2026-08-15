import AppKit
import LuminaCore
import SwiftUI
import UniformTypeIdentifiers
#if LUMINA_NATIVE_LOCAL
import LuminaNativeLock
#endif

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection = .general

    var body: some View {
        VStack(spacing: 0) {
            settingsContent
            Divider()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    model.shutdown()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit \(model.appDisplayName)", systemImage: "power")
                }
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .alert(
            "Shortcut Permission Repair Needed",
            isPresented: Binding(
                get: { model.isShortcutPermissionRecoveryPresented },
                set: { if !$0 { model.dismissShortcutPermissionRecovery() } }
            )
        ) {
            Button("Open Accessibility Settings") {
                model.openAccessibilitySettings()
            }
            Button("Open Input Monitoring Settings") {
                model.openInputMonitoringSettings()
            }
            Button("Later", role: .cancel) {
                model.dismissShortcutPermissionRecovery()
            }
        } message: {
            Text(model.shortcutPermissionRecoveryMessage)
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if model.contents.isEmpty {
            WelcomeView(model: model)
        } else {
            TabView(selection: $selection) {
                GeneralSettingsView(model: model)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsSection.general)
                AppearanceSettingsView(model: model)
                    .tabItem { Label("Appearance", systemImage: "paintbrush") }
                    .tag(SettingsSection.appearance)
                if model.isNativeLocalBuild {
                    NativeLockSettingsView(model: model)
                        .tabItem { Label("Native Lock", systemImage: "lock.display") }
                        .tag(SettingsSection.nativeLock)
                } else {
                    ScreenSaverSettingsView(model: model)
                        .tabItem { Label("Screen Saver", systemImage: "display") }
                        .tag(SettingsSection.screenSaver)
                }
                AboutView(model: model)
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(SettingsSection.about)
            }
            .padding(20)
            .alert(
                model.attentionTitle,
                isPresented: Binding(
                    get: { model.presentedError != nil },
                    set: { if !$0 { model.presentedError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.presentedError ?? "")
            }
        }
    }
}

private enum SettingsSection: Hashable {
    case general
    case appearance
    case screenSaver
    case nativeLock
    case about
}

private struct WelcomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            LuminaIconPreview(
                image: model.appIconImage,
                size: 82
            )
            VStack(spacing: 8) {
                Text("Welcome to \(model.appDisplayName)")
                    .font(.largeTitle.bold())
                Text(
                    localized(
                        model.isNativeLocalBuild
                            ? "Choose a video and Hikari will copy it into a managed library,\nthen play it quietly behind your desktop."
                            : "Choose a video and Lumina will copy it into a managed library,\nthen play it quietly behind your desktop."
                    )
                )
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Label("Choose a video from anywhere on your Mac", systemImage: "folder")
                    .font(.headline)
                Text("You do not need to move it manually. \(model.appDisplayName) stores its copy in:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(model.managedMediaDirectoryDisplayPath)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(14)
            .frame(maxWidth: 460)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            Button {
                chooseVideo()
            } label: {
                Label(
                    localized(model.isImporting ? "Importing…" : "Choose Video…"),
                    systemImage: "plus"
                )
                .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isImporting)
            Text("Your original file is never modified.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(36)
        .alert(
            model.attentionTitle,
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { if !$0 { model.presentedError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.presentedError ?? "")
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFileSupport.pickerContentTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.importVideo(from: url)
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: model.setLaunchAtLogin
                    )
                ) {
                    Text(
                        localized(
                            model.isNativeLocalBuild
                                ? "Launch Hikari at login"
                                : "Launch Lumina at login"
                        )
                    )
                }
                Toggle(
                    "Pause while on battery",
                    isOn: Binding(
                        get: { model.settings.pauseOnBattery },
                        set: model.setPauseOnBattery
                    )
                )
                Toggle(
                    "Mute video",
                    isOn: Binding(
                        get: { model.settings.isMuted },
                        set: model.setMuted
                    )
                )
            } header: {
                Text("Playback")
            } footer: {
                Text(
                    localized(
                        model.isNativeLocalBuild
                            ? "Hikari keeps the macOS wallpaper and menu bar unchanged. "
                                + "Playback pauses while the Mac is locked or asleep."
                            : "Lumina keeps the macOS wallpaper and menu bar unchanged. "
                                + "Playback pauses while the Mac is locked or asleep."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pendingDeletion: LiveContent?

    var body: some View {
        Form {
            Section("App Icon") {
                HStack(spacing: 16) {
                    ForEach(AppIconStyle.allCases) { style in
                        Button {
                            if style == .custom {
                                chooseCustomIcon()
                            } else {
                                model.setAppIconStyle(style)
                            }
                        } label: {
                            VStack(spacing: 8) {
                                LuminaIconPreview(
                                    image: model.appIconImage(for: style),
                                    size: 64
                                )
                                Text(appIconDisplayName(for: style))
                                    .font(.caption)
                            }
                            .padding(8)
                            .background(
                                model.settings.appIconStyle == style
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        model.settings.appIconStyle == style
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            String(
                                format: NSLocalizedString(
                                    "%@ app icon",
                                    comment: "App icon option accessibility label"
                                ),
                                appIconDisplayName(for: style)
                            )
                        )
                    }
                }
                Text(
                    localized(
                        model.isNativeLocalBuild
                            ? "Choose a preset or import your own image. Your choice is used "
                                + "by Hikari in Finder, Spotlight, and the app switcher. "
                                + "The menu bar icon has its own setting below."
                            : "Choose a preset or import your own image. Your choice is used "
                                + "by Lumina in Finder, Spotlight, and the app switcher. "
                                + "The menu bar icon has its own setting below."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Menu Bar Icon") {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 92), spacing: 12)],
                    spacing: 14
                ) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Button {
                            if style == .custom {
                                chooseCustomMenuBarIcon()
                            } else {
                                model.setMenuBarIconStyle(style)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                MenuBarIconPreview(
                                    image: model.menuBarIconImage(for: style),
                                    size: 58,
                                    isTemplate: style.isTemplate
                                )
                                Text(menuBarIconDisplayName(for: style))
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(6)
                            .background(
                                model.settings.menuBarIconStyle == style
                                    ? Color.accentColor.opacity(0.16)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        model.settings.menuBarIconStyle == style
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(
                    localized(
                        "This icon is independent from the app icon and appears only in the menu bar."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Scaling") {
                Picker(
                    "Video scaling",
                    selection: Binding(
                        get: { model.settings.scalingMode },
                        set: model.setScalingMode
                    )
                ) {
                    Text("Fill").tag(ScalingMode.fill)
                    Text("Fit").tag(ScalingMode.fit)
                }
                .pickerStyle(.segmented)
                Text(
                    localized(
                        model.settings.scalingMode == .fill
                            ? "Fills each display; some edges may be cropped."
                            : "Shows the whole video; letterboxing may appear."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Library") {
                ForEach(model.contents) { content in
                    HStack(spacing: 12) {
                        ThumbnailView(url: model.thumbnailURL(for: content))
                            .frame(width: 72, height: 44)
                        VStack(alignment: .leading) {
                            Text(content.title)
                            Text(
                                "\(content.width) × \(content.height) · "
                                    + durationText(content.duration)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if content.id == model.selectedContent?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("Selected")
                        } else {
                            Button("Use") {
                                model.select(content)
                            }
                        }
                        Button(role: .destructive) {
                            pendingDeletion = content
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(content.title)")
                    }
                    .padding(.vertical, 3)
                }
                Button {
                    chooseVideo()
                } label: {
                    Label("Import Video…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            localized(
                model.isNativeLocalBuild
                    ? "Delete this video from Hikari?"
                    : "Delete this video from Lumina?"
            ),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let content = pendingDeletion {
                    model.delete(content)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("The original video will not be changed.")
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFileSupport.pickerContentTypes
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.importVideo(from: url)
        }
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = localized(
            model.isNativeLocalBuild
                ? "Choose an image for your custom Hikari icon."
                : "Choose an image for your custom Lumina icon."
        )
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importCustomAppIcon(from: url)
    }

    private func chooseCustomMenuBarIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = localized("Choose an image for your custom menu bar icon.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importCustomMenuBarIcon(from: url)
    }

    private func durationText(_ duration: Double) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func appIconDisplayName(for style: AppIconStyle) -> String {
        model.isNativeLocalBuild && style == .lumina
            ? model.appDisplayName
            : style.localizedName
    }

    private func menuBarIconDisplayName(for style: MenuBarIconStyle) -> String {
        model.isNativeLocalBuild && style == .lumina
            ? model.appDisplayName
            : style.localizedName
    }
}

private struct ScreenSaverSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Installation") {
                    Label(
                        localized(model.isScreenSaverInstalled ? "Installed" : "Not installed"),
                        systemImage: model.isScreenSaverInstalled
                            ? "checkmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                    .foregroundStyle(model.isScreenSaverInstalled ? .green : .secondary)
                }

                LabeledContent("Selected Screen Saver") {
                    Label(
                        localized(
                            model.isScreenSaverSelected
                                ? "Lumina"
                                : "Mac default"
                        ),
                        systemImage: model.isScreenSaverSelected
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.isScreenSaverSelected ? .green : .orange)
                }

                LabeledContent("Automatic Start") {
                    Label(
                        startDelayText,
                        systemImage: model.screenSaverStartDelay > 0
                            ? "timer"
                            : "timer.square"
                    )
                    .foregroundStyle(
                        model.screenSaverStartDelay > 0
                            ? Color.primary
                            : Color.orange
                    )
                }

                Toggle(
                    "Play video on Lock Screen",
                    isOn: Binding(
                        get: { model.isLockScreenPlaybackEnabled },
                        set: model.setLockScreenPlayback
                    )
                )
                .disabled(
                    !model.isScreenSaverInstalled
                        || !model.isScreenSaverSelected
                )

                Toggle(
                    isOn: Binding(
                        get: { model.settings.overrideSystemLockShortcut },
                        set: model.setLockShortcutOverride
                    )
                ) {
                    HStack {
                        Text("Use shortcut for Lumina Lock")
                        Spacer()
                        ShortcutKeyCapsView()
                    }
                }
                .disabled(
                    !model.isScreenSaverInstalled
                        || !model.isScreenSaverSelected
                        || model.selectedContent == nil
                )

                LabeledContent("Shortcut Status") {
                    Label(
                        localized(
                            model.isLockShortcutOverrideActive
                                ? "Active"
                                : model.settings.overrideSystemLockShortcut
                                    ? "Accessibility and Input Monitoring permission required"
                                    : "Mac default"
                        ),
                        systemImage: model.isLockShortcutOverrideActive
                            ? "checkmark.circle.fill"
                            : "keyboard"
                    )
                    .foregroundStyle(
                        model.isLockShortcutOverrideActive ? .green : .secondary
                    )
                }

                if model.settings.overrideSystemLockShortcut {
                    LabeledContent("Accessibility") {
                        permissionLabel(
                            granted: model.isAccessibilityPermissionGranted
                        )
                    }

                    LabeledContent("Input Monitoring") {
                        permissionLabel(
                            granted: model.isInputMonitoringPermissionGranted
                        )
                    }

                    if !model.isLockShortcutOverrideActive {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.shortcutPermissionRecoveryMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Request Permissions") {
                                    model.requestShortcutPermissions()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Recheck Permissions") {
                                    model.recheckShortcutPermissions()
                                }
                            }

                            HStack {
                                Button("Open Accessibility Settings") {
                                    model.openAccessibilitySettings()
                                }
                                Button("Open Input Monitoring Settings") {
                                    model.openInputMonitoringSettings()
                                }
                            }
                        }
                    }
                }

                if model.isScreenSaverInstalled {
                    HStack {
                        Button("Preview Lumina") {
                            model.previewScreenSaver()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            !model.isScreenSaverSelected
                                || model.selectedContent == nil
                        )

                        Button("Choose Screen Saver") {
                            model.openScreenSaverSettings()
                        }

                        Button("Set Start Time") {
                            model.openLockScreenSettings()
                        }

                        Button("Lock with Lumina") {
                            model.lockWithLumina()
                        }
                    }
                } else {
                    Button("Install Screen Saver") {
                        model.installScreenSaver()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if model.isScreenSaverInstalled {
                    Button(
                        model.isScreenSaverUpdateAvailable
                            ? "Update Lumina Screen Saver"
                            : "Reinstall Lumina Screen Saver"
                    ) {
                        model.installScreenSaver()
                    }
                }
            } header: {
                Text("Lumina Screen Saver")
            } footer: {
                Text(
                    localized(
                        "Lumina Lock starts the video screen saver immediately. For a secure "
                            + "lock, set Require password after screen saver begins to Immediately. "
                            + "The optional shortcut override needs Accessibility and Input Monitoring permissions."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }

    private var startDelayText: String {
        guard model.screenSaverStartDelay > 0 else {
            return localized("Never")
        }
        return String(
            format: NSLocalizedString(
                "After %d minutes",
                comment: "Screen saver automatic start delay"
            ),
            max(1, model.screenSaverStartDelay / 60)
        )
    }

    private func permissionLabel(granted: Bool) -> some View {
        Label(
            localized(granted ? "Granted" : "Required"),
            systemImage: granted
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
        )
        .foregroundStyle(granted ? Color.green : Color.orange)
    }
}

private struct NativeLockSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                #if LUMINA_NATIVE_LOCAL
                let report = NativeLockSafetyInspector.evaluate(
                    hasSelectedMedia: model.selectedContent != nil,
                    transactionPhase: model.nativeLockPhase
                )
                LabeledContent("Safety Status") {
                    Label(localized(report.title), systemImage: "lock.shield.fill")
                        .foregroundStyle(
                            report.state == .active ? Color.green : Color.orange
                        )
                }
                Text(localized(report.detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if NativeLockUpgradeGuard
                    .requiresRestoreBeforeMajorOperatingSystemUpdate(
                        transactionPhase: model.nativeLockPhase
                    ) {
                    Label {
                        Text(
                            localized(
                                "Before installing a new macOS major version, restore Hikari from this screen. An unfinished Native Lock transaction may not be recoverable after the update."
                            )
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .background(
                        Color.orange.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                }

                if let title = model.nativeLockAppliedContentTitle,
                   model.nativeLockPhase != .restored {
                    LabeledContent("Applied video") {
                        Text(title)
                            .lineLimit(1)
                    }
                }

                HStack {
                    Button {
                        model.applySelectedVideoToNativeLock()
                    } label: {
                        if model.isNativeLockWorking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Apply Selected Video")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        report.state != .ready || model.isNativeLockWorking
                    )

                    if model.nativeLockPhase != nil,
                       model.nativeLockPhase != .restored {
                        Button("Restore Previous Wallpaper") {
                            model.restoreNativeLock()
                        }
                        .disabled(model.isNativeLockWorking)
                    }
                }
                #else
                Text("Native Lock is available only in the Hikari Native Local target.")
                    .foregroundStyle(.secondary)
                #endif
            } header: {
                Text("Native Lock (Local)")
            }

            Section {
                LabeledContent("System lock shortcut") {
                    HStack(spacing: 8) {
                        Text("Supported (system-owned)")
                        ShortcutKeyCapsView()
                    }
                }
                LabeledContent("Automatic updates") {
                    Text("Disabled")
                }
                LabeledContent("Managed media") {
                    Text(model.managedMediaDirectoryDisplayPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Text("Isolation")
            } footer: {
                Text(
                    localized(
                        "Native Local supports Control-Command-Q through the macOS system lock path instead of intercepting it. Apply creates verified backups and journals before changing the private macOS aerial store. Restore returns the saved wallpaper mapping and removes only Hikari-owned system assets."
                    )
                )
            }
        }
        .formStyle(.grouped)
    }
}

private func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private struct AboutView: View {
    @ObservedObject var model: AppModel
    @State private var showingUpdateConfirmation = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            LuminaIconPreview(
                image: model.appIconImage,
                size: 78
            )
            Text(model.appDisplayName)
                .font(.title.bold())
            Text("Version \(model.currentAppVersion)")
                .foregroundStyle(.secondary)
            Text("Native live wallpaper and screen saver for macOS.")
                .foregroundStyle(.secondary)
            Link(
                "GitHub Repository",
                destination: URL(string: "https://github.com/hodadako/lumina")!
            )
            Text("Released under the MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Divider()
            if model.supportsAutomaticUpdates {
                VStack(spacing: 8) {
                switch model.updateCheckState {
                case .checking:
                    ProgressView("Checking for updates…")
                case .updateAvailable:
                    if let release = model.latestRelease {
                        Text(
                            String(
                                format: NSLocalizedString(
                                    "Version %@ is available.",
                                    comment: "Available app update message"
                                ),
                                release.displayVersion
                            )
                        )
                        .foregroundStyle(.tint)
                        Button("Update and Relaunch") {
                            showingUpdateConfirmation = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isApplyingUpdate)
                    }
                case .upToDate:
                    Text("Lumina is up to date.")
                        .foregroundStyle(.secondary)
                case .failed:
                    Text(model.updateErrorMessage ?? "Could not check for updates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .idle:
                    EmptyView()
                }

                Button(
                    model.isApplyingUpdate
                        ? "Preparing Update…"
                        : "Check for Updates"
                ) {
                    model.checkForUpdates()
                }
                .disabled(
                    model.isApplyingUpdate
                        || model.updateCheckState == .checking
                )
                }
            } else {
                Label(
                    "Local source build — automatic updates disabled",
                    systemImage: "hammer"
                )
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "Install Lumina update?",
            isPresented: $showingUpdateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update and Relaunch") {
                model.applyLatestUpdate()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let release = model.latestRelease {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Lumina will download %@, replace the current app, and relaunch.",
                            comment: "App update confirmation message"
                        ),
                        release.displayVersion
                    )
                )
            }
        }
    }
}
