import AppKit
import Combine
import HikariCore

/// Checks release metadata independently of installation. An active Native Lock
/// transaction may block installation, but must not hide a new release.
@MainActor
final class AppUpdateMonitor: ObservableObject {
    @Published private(set) var latestRelease: LatestRelease?
    @Published private(set) var state: UpdateCheckState = .idle
    @Published private(set) var errorMessage: String?

    private static let checkInterval: TimeInterval = 24 * 60 * 60
    private enum Key {
        static let lastCheck = "hikari.updates.lastCheckAttempt"
        static let cachedRelease = "hikari.updates.cachedRelease"
        static let notifiedVersion = "hikari.updates.notifiedVersion"
    }

    private let currentVersion: HikariVersion?
    private let defaults: UserDefaults
    private let fetch: () async throws -> LatestRelease
    private let notify: (LatestRelease) async -> Bool
    private let now: () -> Date
    private var checkTask: Task<Void, Never>?
    private var checkID: UUID?
    private var scheduleTask: Task<Void, Never>?
    private var wakeToken: NSObjectProtocol?

    init(
        currentVersion: String,
        defaults: UserDefaults = .standard,
        fetch: @escaping () async throws -> LatestRelease = {
            try await ReleaseUpdateService().fetchLatestRelease()
        },
        notify: @escaping (LatestRelease) async -> Bool = {
            await UpdateNotificationService().post(for: $0)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = HikariVersion(currentVersion)
        self.defaults = defaults
        self.fetch = fetch
        self.notify = notify
        self.now = now
        if let data = defaults.data(forKey: Key.cachedRelease),
           let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
           (try? validate(release)) != nil {
            latestRelease = release
            state = hasUpdateAvailable ? .updateAvailable : .upToDate
        }
    }

    var hasUpdateAvailable: Bool {
        guard let version = latestRelease?.version, let currentVersion else {
            return false
        }
        return version > currentVersion
    }

    func start() {
        guard scheduleTask == nil else { return }
        checkForUpdates(automatically: true)
        // A low-frequency eligibility check also covers apps left running for
        // days. Sleep does not accumulate missed timer ticks.
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3600), clock: .suspending)
                } catch { return }
                guard !Task.isCancelled else { return }
                self?.checkForUpdates(automatically: true)
            }
        }
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates(automatically: true)
            }
        }
    }

    func stop() {
        scheduleTask?.cancel()
        scheduleTask = nil
        checkTask?.cancel()
        checkTask = nil
        checkID = nil
        if let wakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeToken)
            self.wakeToken = nil
        }
        if state == .checking {
            state = latestRelease == nil ? .idle
                : (hasUpdateAvailable ? .updateAvailable : .upToDate)
        }
    }

    @discardableResult
    func checkForUpdates(automatically: Bool = false) -> Task<Void, Never>? {
        if let checkTask { return checkTask }
        let date = now()
        if automatically, let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date {
            let elapsed = date.timeIntervalSince(lastCheck)
            // A clock correction must not defer checks indefinitely.
            if elapsed >= 0 && elapsed < Self.checkInterval { return nil }
        }
        // Throttle attempts, including offline failures, across app restarts.
        // A manual check always bypasses this throttle.
        defaults.set(date, forKey: Key.lastCheck)
        errorMessage = nil
        state = .checking
        let id = UUID()
        checkID = id
        let fetch = self.fetch
        checkTask = Task { [weak self] in
            defer {
                if self?.checkID == id { self?.checkTask = nil }
            }
            do {
                let release = try await fetch()
                guard let self, !Task.isCancelled else { return }
                let version = try self.validate(release)
                self.latestRelease = release
                self.defaults.set(try JSONEncoder().encode(release), forKey: Key.cachedRelease)
                self.state = self.hasUpdateAvailable ? .updateAvailable : .upToDate
                let notifiedVersion = self.defaults.string(forKey: Key.notifiedVersion)
                    .flatMap(HikariVersion.init)
                if automatically, self.hasUpdateAvailable,
                   notifiedVersion.map({ version > $0 }) ?? true,
                   await self.notify(release), !Task.isCancelled {
                    self.defaults.set(version.description, forKey: Key.notifiedVersion)
                }
            } catch {
                guard let self, !Task.isCancelled else { return }
                if automatically {
                    // Keep a known available release visible through an outage.
                    self.state = self.latestRelease == nil ? .idle
                        : (self.hasUpdateAvailable ? .updateAvailable : .upToDate)
                } else {
                    self.state = .failed
                    self.errorMessage = error.localizedDescription
                }
            }
        }
        return checkTask
    }

    private func validate(_ release: LatestRelease) throws -> HikariVersion {
        guard let version = release.version, currentVersion != nil else {
            throw ReleaseUpdateError.invalidReleaseVersion
        }
        guard release.archiveAsset != nil else { throw ReleaseUpdateError.releaseArchiveMissing }
        guard release.checksumAsset != nil else { throw ReleaseUpdateError.checksumMissing }
        return version
    }

    deinit {
        scheduleTask?.cancel()
        checkTask?.cancel()
        if let wakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeToken)
        }
    }
}
