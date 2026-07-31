import AppKit
import LuminaCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection = .general

    var body: some View {
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
                ScreenSaverSettingsView(model: model)
                    .tabItem { Label("Screen Saver", systemImage: "display") }
                    .tag(SettingsSection.screenSaver)
                AboutView()
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(SettingsSection.about)
            }
            .padding(20)
            .alert(
                "Lumina Needs Attention",
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
    case about
}

private struct WelcomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "sparkles.tv")
                .font(.system(size: 54, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Welcome to Lumina")
                    .font(.largeTitle.bold())
                Text("Choose an MP4 and Lumina will copy it into a managed library,\nthen play it quietly behind your desktop.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                Label("Choose an MP4 from anywhere on your Mac", systemImage: "folder")
                    .font(.headline)
                Text("You do not need to move it manually. Lumina stores its copy in:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("~/Library/Application Support/Lumina/Media")
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
                    model.isImporting ? "Importing…" : "Choose MP4…",
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
            "Lumina Needs Attention",
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
        panel.allowedContentTypes = [.mpeg4Movie]
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
                    "Launch Lumina at login",
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
            } header: {
                Text("Playback")
            } footer: {
                Text("Lumina always pauses while the Mac is locked or asleep.")
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
                    model.settings.scalingMode == .fill
                        ? "Fills each display; some edges may be cropped."
                        : "Shows the whole video; letterboxing may appear."
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
                    Label("Import MP4…", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete this video from Lumina?",
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
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.importVideo(from: url)
        }
    }

    private func durationText(_ duration: Double) -> String {
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ScreenSaverSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(
                        model.isScreenSaverInstalled
                            ? "Installed — selection required"
                            : "Not installed",
                        systemImage: model.isScreenSaverInstalled
                            ? "exclamationmark.circle.fill"
                            : "exclamationmark.circle"
                    )
                    .foregroundStyle(model.isScreenSaverInstalled ? .orange : .secondary)
                }

                if model.isScreenSaverInstalled {
                    VStack(alignment: .leading, spacing: 12) {
                        setupStep(
                            number: 1,
                            title: "Open System Settings",
                            detail: "Lumina opens the macOS Screen Saver panel."
                        )
                        setupStep(
                            number: 2,
                            title: "Select Lumina",
                            detail: "Choose Lumina under Custom or Other."
                        )
                        setupStep(
                            number: 3,
                            title: "Set the start time",
                            detail: "In Lock Screen settings, allow the screen saver "
                                + "to start before the display turns off."
                        )
                    }
                    .padding(.vertical, 6)

                    Button("Choose Lumina in System Settings") {
                        model.openScreenSaverSettings()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(
                        "Install Screen Saver"
                    ) {
                        model.installScreenSaver()
                    }
                }

                if model.isScreenSaverInstalled {
                    Button("Reinstall Lumina Screen Saver") {
                        model.installScreenSaver()
                    }
                }
            } header: {
                Text("Lumina Screen Saver")
            } footer: {
                Text(
                    "macOS requires you to confirm the screen saver selection. "
                        + "Immediately after locking, the existing Lock Screen background "
                        + "may remain visible until the screen saver starts."
                )
            }
        }
        .formStyle(.grouped)
    }

    private func setupStep(
        number: Int,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(.tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles.tv")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tint)
            Text("Lumina")
                .font(.title.bold())
            Text("Version \(appVersion)")
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
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
    }
}
