import AppKit
import LuminaCore
import LuminaNativeLock
import SwiftUI
import UniformTypeIdentifiers

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
                AboutView(model: model)
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(SettingsSection.about)
            }
            .padding(20)
        }
    }
}

private enum SettingsSection: Hashable {
    case general
    case about
}

private struct WelcomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            HikariIconPreview(image: model.appIconImage, size: 82)
            VStack(spacing: 8) {
                Text("Welcome to \(model.appDisplayName)")
                    .font(.largeTitle.bold())
                Text(
                    "Choose a video and Hikari will copy it into a managed library,\n"
                        + "then play it quietly behind your desktop."
                )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Label("Choose a video from anywhere on your Mac", systemImage: "folder")
                    .font(.headline)
                Text("You do not need to move it manually. Hikari stores its copy in:")
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
                    model.isImporting ? "Importing…" : "Choose Video…",
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
        Task { await model.importVideo(from: url) }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var pendingDeletion: LiveContent?

    var body: some View {
        Form {
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
                            Button("Use") { model.select(content) }
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
                Button { chooseVideo() } label: {
                    Label("Import Video…", systemImage: "plus")
                }
            }

            Section("Playback") {
                Toggle(
                    "Launch Hikari at login",
                    isOn: Binding(
                        get: { model.settings.launchAtLogin },
                        set: model.setLaunchAtLogin
                    )
                )
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
            }

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
                                HikariIconPreview(
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
                    }
                }
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
            }

            NativeLockStatusSection(model: model)
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete this video from Hikari?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let content = pendingDeletion { model.delete(content) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The original video will not be changed.")
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFileSupport.pickerContentTypes
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.importVideo(from: url) }
    }

    private func chooseCustomIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image for your custom Hikari icon."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importCustomAppIcon(from: url)
    }

    private func chooseCustomMenuBarIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image for your custom menu bar icon."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importCustomMenuBarIcon(from: url)
    }

    private func durationText(_ duration: Double) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func appIconDisplayName(for style: AppIconStyle) -> String {
        style == .lumina ? model.appDisplayName : style.localizedName
    }

    private func menuBarIconDisplayName(for style: MenuBarIconStyle) -> String {
        style == .lumina ? model.appDisplayName : style.localizedName
    }
}

/// Native Lock is automatic on macOS 26: selecting a video from General
/// updates the Aerial transaction after a short debounce. This section is
/// deliberately not a separate settings tab; it exposes only the recovery
/// actions that must remain available while a transaction owns system state.
private struct NativeLockStatusSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
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

            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
               report.state != .recoveryRequired {
                Text(
                    "Changing the selected video automatically updates the Lock Screen."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            if NativeLockUpgradeGuard
                .requiresRestoreBeforeMajorOperatingSystemUpdate(
                    transactionPhase: model.nativeLockPhase
                ) {
                Label {
                    Text(
                        "Before installing a new macOS major version, restore Hikari from this screen. An unfinished Lock Screen change may not be recoverable after the update."
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
                    Text(title).lineLimit(1)
                }
            }

            HStack {
                if ProcessInfo.processInfo.operatingSystemVersion.majorVersion != 26 {
                    Button {
                        model.applySelectedVideoToNativeLock()
                    } label: {
                        if model.isNativeLockWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Apply Selected Video")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(report.state != .ready || model.isNativeLockWorking)
                }

                if model.canDiscardKnownNoopNativeLockPreflight {
                    Button("Clear Failed Preparation") {
                        model.discardKnownNoopNativeLockPreflight()
                    }
                    .disabled(model.isNativeLockWorking)
                } else if model.nativeLockPhase != nil,
                          model.nativeLockPhase != .restored {
                    Button("Restore Previous Wallpaper") {
                        model.restoreNativeLock()
                    }
                    .disabled(model.isNativeLockWorking)
                }
            }
        } header: {
            Text("Lock Screen")
        } footer: {
            Text(
                "Hikari uses macOS's native Lock Screen path. Restore an unfinished transaction before updating the app or macOS."
            )
        }
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
            HikariIconPreview(image: model.appIconImage, size: 78)
            Text(model.appDisplayName).font(.title.bold())
            Text("Version \(model.currentAppVersion)")
                .foregroundStyle(.secondary)
            Text("Native live wallpaper for macOS.")
                .foregroundStyle(.secondary)
            Link(
                "GitHub Repository",
                destination: URL(string: "https://github.com/hodadako/hikari")!
            )
            Text("Released under the MIT License")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(
                "Release builds are ad-hoc signed. macOS may show a first-launch security warning, and these builds are not notarized."
            )
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Divider()

            if let reason = model.updateBlockedReason {
                Label(reason, systemImage: "lock.shield")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            } else {
                updateControls
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog(
            "Install Hikari update?",
            isPresented: $showingUpdateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update and Relaunch") { model.applyLatestUpdate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let release = model.latestRelease {
                Text(
                    String(
                        format: NSLocalizedString(
                            "Hikari will download %@, replace the current app, and relaunch.",
                            comment: "App update confirmation message"
                        ),
                        release.displayVersion
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var updateControls: some View {
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
                Text("Hikari is up to date.").foregroundStyle(.secondary)
            case .failed:
                Text(model.updateErrorMessage ?? "Could not check for updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .idle:
                EmptyView()
            }

            Button(
                model.isApplyingUpdate ? "Preparing Update…" : "Check for Updates"
            ) {
                model.checkForUpdates()
            }
            .disabled(
                model.isApplyingUpdate || model.updateCheckState == .checking
            )
        }
    }
}
