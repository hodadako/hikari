import AppKit
import LuminaCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @State private var showingImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            currentContentHeader
            Divider()

            Button {
                model.togglePlayback()
            } label: {
                Label(
                    localized(
                        model.isPlaying ? "Pause Wallpaper" : "Play Wallpaper"
                    ),
                    systemImage: model.isPlaying ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(model.selectedContent == nil)
            .keyboardShortcut(.space, modifiers: [])

            Menu {
                ForEach(model.contents) { content in
                    Button {
                        model.select(content)
                    } label: {
                        if content.id == model.selectedContent?.id {
                            Label(content.title, systemImage: "checkmark")
                        } else {
                            Text(content.title)
                        }
                    }
                }
                if !model.contents.isEmpty {
                    Divider()
                }
                Button("Import MP4…") {
                    chooseVideo()
                }
            } label: {
                Label("Change Content", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                showSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if model.isScreenSaverInstalled {
                    model.openScreenSaverSettings()
                } else {
                    model.installScreenSaver()
                }
            } label: {
                Label(
                    localized(
                        model.isScreenSaverInstalled
                            ? "Finish Screen Saver Setup"
                            : "Set Up Screen Saver"
                    ),
                    systemImage: "rectangle.inset.filled.and.person.filled"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                model.previewScreenSaver()
            } label: {
                Label(
                    "Preview Lumina Screen Saver",
                    systemImage: "play.rectangle.on.rectangle"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(
                !model.isScreenSaverInstalled
                    || !model.isScreenSaverSelected
                    || model.selectedContent == nil
            )

            Button {
                model.lockWithLumina()
            } label: {
                HStack {
                    Label("Lock with Lumina", systemImage: "lock.fill")
                    Spacer()
                    ShortcutKeyCapsView(compact: true)
                }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(
                !model.isScreenSaverInstalled
                    || !model.isScreenSaverSelected
                    || model.selectedContent == nil
            )

            Divider()
            Button {
                model.shutdown()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Lumina", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 300)
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

    @ViewBuilder
    private var currentContentHeader: some View {
        if let content = model.selectedContent {
            HStack(spacing: 12) {
                ThumbnailView(url: model.thumbnailURL(for: content))
                    .frame(width: 72, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.isPlaying ? "Playing" : pauseStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.tv")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bring your desktop to life")
                        .font(.headline)
                    Text("Import an MP4 to begin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pauseStatus: String {
        if model.pauseReasons.contains(.user) { return localized("Paused") }
        if model.pauseReasons.contains(.battery) {
            return localized("Paused on battery")
        }
        if model.pauseReasons.contains(.screenSaver) {
            return localized("Screen saver active")
        }
        if model.pauseReasons.contains(.screenLock) {
            return localized("Screen locked")
        }
        if model.pauseReasons.contains(.sleep) {
            return localized("Display asleep")
        }
        return localized("Ready")
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = localized("Choose an MP4 video for your Lumina wallpaper.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await model.importVideo(from: url)
        }
    }

    private func showSettings() {
        SettingsWindowPresenter.shared.show(model: model)
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "film")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("Current video thumbnail")
    }
}
