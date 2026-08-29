import Foundation

/// A display description that can be used without AppKit. `id` is the
/// CGDirectDisplayID when the app is running on macOS.
public struct DisplayDescriptor: Equatable, Hashable, Sendable {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let backingScaleFactor: Double
    public let isMain: Bool

    public init(
        id: UInt32,
        frame: CGRect,
        visibleFrame: CGRect,
        backingScaleFactor: Double,
        isMain: Bool
    ) {
        self.id = id
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.isMain = isMain
    }
}

public struct WallpaperWindowPlan: Equatable, Hashable, Sendable {
    public let displayID: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let backingScaleFactor: Double
    public let isMain: Bool

    public init(descriptor: DisplayDescriptor) {
        displayID = descriptor.id
        frame = descriptor.frame
        visibleFrame = descriptor.visibleFrame
        backingScaleFactor = descriptor.backingScaleFactor
        isMain = descriptor.isMain
    }
}

public struct DisplayTopologyDiff: Equatable, Sendable {
    public let created: [WallpaperWindowPlan]
    public let updated: [WallpaperWindowPlan]
    public let removed: [UInt32]
    public let unchanged: [UInt32]

    public init(
        created: [WallpaperWindowPlan],
        updated: [WallpaperWindowPlan],
        removed: [UInt32],
        unchanged: [UInt32]
    ) {
        self.created = created
        self.updated = updated
        self.removed = removed
        self.unchanged = unchanged
    }
}

public enum DisplayRecoveryPass: Equatable, Sendable {
    case topology
    case settled
}

public enum DisplayRecoveryPolicy {
    public static func passes(
        for intervals: [UInt64]
    ) -> [DisplayRecoveryPass] {
        intervals.indices.map { index in
            index == intervals.count - 1 ? .settled : .topology
        }
    }
}

public enum ActiveSpaceRecoveryDisposition: Equatable, Sendable {
    case preserveSurfaces
    case rebuildSurfaces
}

/// Coordinates display and Space recovery notifications that WindowServer can
/// emit for the same physical display transition.
///
/// A display attach/detach can materialize per-display Spaces and publish an
/// `activeSpaceDidChange` notification even though the user did not switch
/// desktops. Rebuilding every wallpaper surface for that derived notification
/// removes all AVPlayerLayer targets and visibly flashes the desktop. A real,
/// independent Space transition still requires the existing surface rebuild.
public struct DisplaySpaceRecoveryState: Equatable, Sendable {
    public private(set) var isDisplayRecoveryInProgress = false

    private var isActiveSpaceRecoveryInProgress = false
    private var activeSpaceDisposition: ActiveSpaceRecoveryDisposition =
        .rebuildSurfaces

    public init() {}

    public mutating func displayRecoveryDidStart() {
        isDisplayRecoveryInProgress = true
        if isActiveSpaceRecoveryInProgress {
            activeSpaceDisposition = .preserveSurfaces
        }
    }

    public mutating func displayRecoveryDidSettle() {
        isDisplayRecoveryInProgress = false
    }

    public mutating func activeSpaceRecoveryDidStart() {
        isActiveSpaceRecoveryInProgress = true
        activeSpaceDisposition = isDisplayRecoveryInProgress
            ? .preserveSurfaces
            : .rebuildSurfaces
    }

    public mutating func activeSpaceRecoveryDidSettle()
        -> ActiveSpaceRecoveryDisposition
    {
        let disposition = activeSpaceDisposition
        isActiveSpaceRecoveryInProgress = false
        activeSpaceDisposition = .rebuildSurfaces
        return disposition
    }
}

public enum DisplayTopology {
    public static func plans(
        for descriptors: [DisplayDescriptor]
    ) -> [WallpaperWindowPlan] {
        var unique: [UInt32: WallpaperWindowPlan] = [:]
        for descriptor in descriptors {
            unique[descriptor.id] = WallpaperWindowPlan(descriptor: descriptor)
        }
        return unique.values.sorted { $0.displayID < $1.displayID }
    }

    public static func diff(
        from oldPlans: [WallpaperWindowPlan],
        to newPlans: [WallpaperWindowPlan]
    ) -> DisplayTopologyDiff {
        let old = Dictionary(
            oldPlans.map { ($0.displayID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let new = Dictionary(
            newPlans.map { ($0.displayID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let created = new.values
            .filter { old[$0.displayID] == nil }
            .sorted { $0.displayID < $1.displayID }
        let updated = new.values
            .filter { old[$0.displayID] != nil && old[$0.displayID] != $0 }
            .sorted { $0.displayID < $1.displayID }
        let removed = old.keys
            .filter { new[$0] == nil }
            .sorted()
        let unchanged = new.values
            .filter { old[$0.displayID] == $0 }
            .map(\.displayID)
            .sorted()

        return DisplayTopologyDiff(
            created: created,
            updated: updated,
            removed: removed,
            unchanged: unchanged
        )
    }
}
