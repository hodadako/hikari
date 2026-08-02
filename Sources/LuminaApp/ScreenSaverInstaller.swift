import AppKit
import CoreFoundation
import LuminaCore

struct ScreenSaverInstaller {
    private let fileManager = FileManager.default

    var contentContainerURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Lumina",
                isDirectory: true
            )
    }

    var installedURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Screen Savers", isDirectory: true)
            .appendingPathComponent("Lumina.saver", isDirectory: true)
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: installedURL.path)
    }

    var isSelected: Bool {
        guard
            let module = currentHostValue(forKey: "moduleDict")
                as? [String: Any],
            module["moduleName"] as? String == "Lumina",
            let path = module["path"] as? String
        else {
            return false
        }
        return URL(fileURLWithPath: path).standardizedFileURL
            == installedURL.standardizedFileURL
    }

    var startDelay: Int {
        (currentHostValue(forKey: "idleTime") as? NSNumber)?.intValue ?? 0
    }

    var isLockScreenPlaybackEnabled: Bool {
        startDelay > 0
    }

    var needsUpdate: Bool {
        guard isInstalled else { return false }
        return version(at: installedURL) != bundledScreenSaverURL.flatMap(version(at:))
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

    func updateIfNeeded() throws {
        guard needsUpdate else { return }
        try install()
    }

    func startPreview() -> Bool {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        )
    }

    func setLockScreenPlaybackEnabled(_ enabled: Bool) -> Bool {
        let delay = enabled ? 60 : 0
        CFPreferencesSetValue(
            "idleTime" as CFString,
            NSNumber(value: delay),
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return CFPreferencesSynchronize(
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openLockScreenSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"
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

    private func version(at url: URL) -> String? {
        Bundle(url: url)?.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String
    }

    private func currentHostValue(forKey key: String) -> Any? {
        CFPreferencesCopyValue(
            key as CFString,
            "com.apple.screensaver" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }
}
