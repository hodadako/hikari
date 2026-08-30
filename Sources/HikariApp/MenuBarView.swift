import AppKit
import HikariCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    let onShowSettings: () -> Void
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
                Button("Import Video…") {
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

            HStack {
                Label("Native Lock", systemImage: "lock.fill")
                Spacer()
                ShortcutKeyCapsView(compact: true)
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            Divider()
            Button {
                model.shutdown()
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit \(model.appDisplayName)", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.plain)
        .padding(14)
        .frame(width: 300)
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
                    Text("Import a video to begin")
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
        guard let url = VideoPicker.chooseVideo(
            startingAt: model.videoPickerDirectoryURL,
            message: localized("Choose a video for your Hikari wallpaper.")
        ) else {
            return
        }
        Task {
            await model.importVideo(from: url)
        }
    }

    private func showSettings() {
        onShowSettings()
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}

struct ThumbnailView: View {
    let url: URL?

    var body: some View {
        ZStack {
            Color.black
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    // Library thumbnails must show the whole video frame.
                    // A portrait frame therefore uses the full thumbnail
                    // height with letterboxing at the sides instead of
                    // escaping its row or cropping its top and bottom.
                    .scaledToFit()
            } else {
                Color.secondary.opacity(0.12)
                Image(systemName: "film")
                    .foregroundStyle(.secondary)
            }
        }
        // The caller supplies the thumbnail's fixed size. Apply that proposed
        // size before clipping: clipping the image at its intrinsic size first
        // lets portrait thumbnails paint outside the enclosing settings row.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("Current video thumbnail")
    }
}
