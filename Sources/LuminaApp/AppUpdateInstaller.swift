import AppKit
import CryptoKit
import Foundation
import LuminaCore

@MainActor
final class AppUpdateInstaller {
    private static let expectedAppName = "Hikari"
    // Keep the existing Native Local bundle identity so Hikari installations
    // can continue to receive in-place updates after the product transition.
    private static let expectedBundleIdentifier = "com.hodadako.Lumina.NativeLocal"
    private let service: ReleaseUpdateService
    private let fileManager = FileManager.default

    init(service: ReleaseUpdateService = ReleaseUpdateService()) {
        self.service = service
    }

    func install(_ release: LatestRelease) async throws {
        guard let releaseVersion = release.version else {
            throw ReleaseUpdateError.invalidReleaseVersion
        }
        guard let archiveAsset = release.archiveAsset else {
            throw ReleaseUpdateError.releaseArchiveMissing
        }
        guard let checksumAsset = release.checksumAsset else {
            throw ReleaseUpdateError.checksumMissing
        }

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(
                "HikariUpdate-\(UUID().uuidString)",
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        var keepTemporaryRoot = false
        defer {
            if !keepTemporaryRoot {
                try? fileManager.removeItem(at: temporaryRoot)
            }
        }

        let archiveURL = try await download(
            archiveAsset,
            to: temporaryRoot.appendingPathComponent(archiveAsset.name)
        )
        let checksumURL = try await download(
            checksumAsset,
            to: temporaryRoot.appendingPathComponent(checksumAsset.name)
        )
        try verifyChecksum(archiveURL: archiveURL, checksumURL: checksumURL)

        let extractionURL = temporaryRoot.appendingPathComponent(
            "extracted",
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: extractionURL,
            withIntermediateDirectories: true
        )
        try run(
            executable: "/usr/bin/ditto",
            arguments: [
                "-x",
                "-k",
                "--sequesterRsrc",
                archiveURL.path,
                extractionURL.path
            ]
        )

        let replacementURL = extractionURL.appendingPathComponent(
            "\(Self.expectedAppName).app",
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: replacementURL.path),
              let replacementBundle = Bundle(url: replacementURL),
              replacementBundle.object(
                  forInfoDictionaryKey: "CFBundleDisplayName"
              ) as? String == Self.expectedAppName,
              replacementBundle.object(
                  forInfoDictionaryKey: "CFBundleIdentifier"
              ) as? String == Self.expectedBundleIdentifier,
              replacementBundle.object(
                  forInfoDictionaryKey: "CFBundleExecutable"
              ) as? String == Self.expectedAppName,
              let replacementVersionString = replacementBundle.object(
                  forInfoDictionaryKey: "CFBundleShortVersionString"
              ) as? String,
              let replacementVersion = LuminaVersion(replacementVersionString),
              replacementVersion == releaseVersion else {
            throw ReleaseUpdateError.extractionFailed
        }
        try run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", replacementURL.path]
        )

        let currentURL = Bundle.main.bundleURL.standardizedFileURL
        let parentURL = currentURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentURL.path) else {
            throw ReleaseUpdateError.replacementNotWritable
        }

        let helperURL = temporaryRoot.appendingPathComponent("install.sh")
        try updateScript.data(using: .utf8)?.write(to: helperURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = [
            helperURL.path,
            String(ProcessInfo.processInfo.processIdentifier),
            currentURL.path,
            replacementURL.path,
            temporaryRoot.path
        ]
        try helper.run()
        keepTemporaryRoot = true
        NSApplication.shared.terminate(nil)
    }

    private func download(_ asset: ReleaseAsset, to destinationURL: URL) async throws -> URL {
        let downloadedURL = try await service.download(asset)
        try fileManager.moveItem(at: downloadedURL, to: destinationURL)
        return destinationURL
    }

    private func verifyChecksum(archiveURL: URL, checksumURL: URL) throws {
        let archiveData = try Data(contentsOf: archiveURL)
        let checksumText = try String(contentsOf: checksumURL, encoding: .utf8)
        guard let expected = checksumText
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .first
            .map(String.init) else {
            throw ReleaseUpdateError.checksumMismatch
        }
        let actual = SHA256.hash(data: archiveData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw ReleaseUpdateError.checksumMismatch
        }
    }

    private func run(executable: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            _ = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw ReleaseUpdateError.extractionFailed
        }
    }

    private var updateScript: String {
        """
        #!/bin/sh
        set -eu

        pid="$1"
        current_app="$2"
        replacement_app="$3"
        temporary_root="$4"
        staged_app="${current_app}.hikari-update-staged"
        backup_app="${current_app}.hikari-update-backup"

        while kill -0 "$pid" >/dev/null 2>&1; do
            sleep 0.2
        done

        rm -rf "$staged_app" "$backup_app"
        ditto --rsrc --extattr --acl "$replacement_app" "$staged_app"
        mv "$current_app" "$backup_app"
        if ! mv "$staged_app" "$current_app"; then
            mv "$backup_app" "$current_app"
            exit 1
        fi

        open "$current_app"
        rm -rf "$backup_app" "$temporary_root"
        """
    }
}
