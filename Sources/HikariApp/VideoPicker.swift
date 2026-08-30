import AppKit
import HikariCore

enum VideoPicker {
    static func chooseVideo(
        startingAt directoryURL: URL,
        message: String? = nil
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = VideoFileSupport.pickerContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = directoryURL
        panel.message = message ?? NSLocalizedString(
            "Choose a video for your Hikari wallpaper.",
            comment: "Video picker message"
        )
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}
