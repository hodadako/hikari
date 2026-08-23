import Darwin
import Foundation
import LuminaNativeLock
import OSLog

private let toolLogger = Logger(
    subsystem: "com.hodadako.Hikari",
    category: "NativeLockTool"
)

/// One-shot entry point embedded in Hikari's ad-hoc release bundle.
@main
struct LuminaNativeTool {
    static func main() {
        do {
            guard getuid() == 0 else {
                throw ToolError.rootRequired
            }
            let arguments = try Arguments.parse(CommandLine.arguments)
            let userHome = try homeDirectory(for: arguments.userID)
            let supportRoot = userHome
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent("Lumina", isDirectory: true)
            let wallpaperIndex = userHome
                .appendingPathComponent(
                    "Library/Application Support/com.apple.wallpaper/Store",
                    isDirectory: true
                )
                .appendingPathComponent("Index.plist")
            let userStore = NativeLockUserTransactionStore(
                supportRootURL: supportRoot,
                wallpaperIndexURL: wallpaperIndex,
                userID: arguments.userID
            )
            let record = try userStore.record(for: arguments.transactionID)
            guard record.request.userID == arguments.userID else {
                throw NativeLockTransactionError.sourceOwnerMismatch
            }
            try validateRequestFile(
                at: userStore.transactionDirectoryURL(
                    for: arguments.transactionID
                ).appendingPathComponent(NativeLockPaths.requestFilename),
                owner: uid_t(arguments.userID)
            )

            let manager = NativeLockSystemTransactionManager(environment: .live)
            let result: NativeLockSystemResult
            toolLogger.notice(
                "Starting \(arguments.operation.rawValue, privacy: .public) for \(arguments.transactionID.uuidString, privacy: .public)"
            )
            try suspendIdleAssetsService()
            defer { refreshIdleAssetsService() }
            switch arguments.operation {
            case .apply:
                result = try manager.apply(
                    request: record.request,
                    sourceTransactionURL: userStore.transactionDirectoryURL(
                        for: arguments.transactionID
                    )
                )
            case .restore:
                result = try manager.restore(request: record.request)
            }
            toolLogger.notice(
                "Finished \(result.operation, privacy: .public) for \(result.transactionID.uuidString, privacy: .public)"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            FileHandle.standardOutput.write(Data("\n".utf8))
        } catch {
            toolLogger.error("Native Lock tool failed: \(error.localizedDescription, privacy: .public)")
            let message = error.localizedDescription
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exit(1)
        }
    }

    private static func homeDirectory(for userID: UInt32) throws -> URL {
        guard let record = getpwuid(uid_t(userID)),
              let home = record.pointee.pw_dir else {
            throw ToolError.userNotFound
        }
        let path = String(cString: home)
        guard path.hasPrefix("/Users/"), !path.contains("..") else {
            throw ToolError.invalidHomeDirectory
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func validateRequestFile(at url: URL, owner: uid_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1 else {
            throw NativeLockTransactionError.sourceNotRegularFile
        }
        guard info.st_uid == owner else {
            throw NativeLockTransactionError.sourceOwnerMismatch
        }
    }

    private static func refreshIdleAssetsService() {
        _ = try? signalIdleAssetsService("-KILL")
    }

    private static func suspendIdleAssetsService() throws {
        let firstStatus = try signalIdleAssetsService("-STOP")
        usleep(100_000)
        // Catch a process that appeared between validation and the first
        // signal without killing the service into a restart loop.
        let secondStatus = try signalIdleAssetsService("-STOP")
        if firstStatus != 0, secondStatus != 0, try idleAssetsServiceIsRunning() {
            throw ToolError.serviceControlFailed
        }
    }

    private static func signalIdleAssetsService(_ signal: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = [signal, "idleassetsd"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func idleAssetsServiceIsRunning() throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "idleassetsd"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}

private struct Arguments {
    enum Operation: String {
        case apply
        case restore
    }

    let operation: Operation
    let userID: UInt32
    let transactionID: UUID

    static func parse(_ values: [String]) throws -> Arguments {
        guard values.count == 6,
              let operation = Operation(rawValue: values[1]),
              values[2] == "--uid",
              let userID = UInt32(values[3]),
              values[4] == "--transaction",
              let transactionID = UUID(uuidString: values[5]) else {
            throw ToolError.invalidArguments
        }
        return Arguments(
            operation: operation,
            userID: userID,
            transactionID: transactionID
        )
    }
}

private enum ToolError: LocalizedError {
    case rootRequired
    case invalidArguments
    case userNotFound
    case invalidHomeDirectory
    case serviceControlFailed

    var errorDescription: String? {
        switch self {
        case .rootRequired:
            "This helper must run with administrator authorization."
        case .invalidArguments:
            "Usage: hikari-native-tool <apply|restore> --uid <uid> --transaction <uuid>"
        case .userNotFound:
            "The requesting local user could not be resolved."
        case .invalidHomeDirectory:
            "The requesting user's home directory is not supported."
        case .serviceControlFailed:
            "The macOS wallpaper asset service could not be suspended safely."
        }
    }
}
