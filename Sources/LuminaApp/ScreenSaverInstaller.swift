import AppKit
import LuminaCore

struct ScreenSaverInstaller {
    private let fileManager = FileManager.default

    var installedURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers", isDirectory: true)
            .appendingPathComponent("Lumina.saver", isDirectory: true)
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: installedURL.path)
    }

    func install() throws {
        guard let bundledURL = bundledScreenSaverURL else {
            throw LuminaError.screenSaverBundleMissing
        }
        let directory = installedURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: installedURL.path) {
            try fileManager.removeItem(at: installedURL)
        }
        try fileManager.copyItem(at: bundledURL, to: installedURL)
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var bundledScreenSaverURL: URL? {
        let candidates = [
            Bundle.main.builtInPlugInsURL?.appendingPathComponent("Lumina.saver"),
            Bundle.main.url(forResource: "Lumina", withExtension: "saver")
        ]
        return candidates.compactMap { $0 }.first {
            fileManager.fileExists(atPath: $0.path)
        }
    }
}
