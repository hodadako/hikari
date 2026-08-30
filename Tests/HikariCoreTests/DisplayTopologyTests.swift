import CoreGraphics
import XCTest
@testable import HikariCore

final class DisplayTopologyTests: XCTestCase {
    private func display(
        _ id: UInt32,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 1920,
        height: CGFloat = 1080,
        scale: Double = 2,
        main: Bool = false
    ) -> DisplayDescriptor {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return DisplayDescriptor(
            id: id,
            frame: frame,
            visibleFrame: frame.insetBy(dx: 0, dy: 24),
            backingScaleFactor: scale,
            isMain: main
        )
    }

    func testSingleBuiltInDisplayCreatesOneWindow() {
        let plans = DisplayTopology.plans(for: [display(1, main: true)])
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans[0].displayID, 1)
        XCTAssertTrue(plans[0].isMain)
    }

    func testBuiltInAndTwoQHDDisplaysCreateThreeWindows() {
        let plans = DisplayTopology.plans(for: [
            display(1, width: 3024, height: 1964, main: true),
            display(2, x: 3024, width: 2560, height: 1440, scale: 1),
            display(3, x: 5584, width: 2560, height: 1440, scale: 1)
        ])
        XCTAssertEqual(plans.map(\.displayID), [1, 2, 3])
        XCTAssertEqual(plans[0].frame.width, 3024)
        XCTAssertEqual(plans[1].backingScaleFactor, 1)
    }

    func testNegativeAndVerticalCoordinatesArePreserved() {
        let plans = DisplayTopology.plans(for: [
            display(2, x: -2560, y: 120),
            display(3, x: 0, y: 1080),
            display(1, main: true)
        ])
        XCTAssertEqual(plans.first { $0.displayID == 2 }?.frame.origin.x, -2560)
        XCTAssertEqual(plans.first { $0.displayID == 3 }?.frame.origin.y, 1080)
    }

    func testMainDisplayChangeIsAnUpdateNotARecreation() {
        let old = DisplayTopology.plans(for: [
            display(1, main: true),
            display(2, x: 1920)
        ])
        let new = DisplayTopology.plans(for: [
            display(1),
            display(2, x: 1920, main: true)
        ])
        let diff = DisplayTopology.diff(from: old, to: new)
        XCTAssertEqual(diff.created, [])
        XCTAssertEqual(diff.removed, [])
        XCTAssertEqual(diff.updated.map(\.displayID), [1, 2])
    }

    func testDisplayRemovalAndAdditionAreDiffedByStableID() {
        let old = DisplayTopology.plans(for: [
            display(1, main: true), display(2, x: 1920), display(3, x: 4480)
        ])
        let new = DisplayTopology.plans(for: [
            display(1, main: true), display(4, x: -2560)
        ])
        let diff = DisplayTopology.diff(from: old, to: new)
        XCTAssertEqual(diff.created.map(\.displayID), [4])
        XCTAssertEqual(diff.removed, [2, 3])
        XCTAssertEqual(diff.unchanged, [1])
    }

    func testRepeatedDisplayNotificationDoesNotCreateDuplicatePlans() {
        let descriptors = [display(1, main: true), display(2, x: 1920)]
        XCTAssertEqual(
            DisplayTopology.plans(for: descriptors + descriptors).count,
            2
        )
    }

    func testDisplayRecoveryRebuildsOnlyAfterTopologySettles() {
        XCTAssertEqual(
            DisplayRecoveryPolicy.passes(for: [0, 250, 650]),
            [.topology, .topology, .settled]
        )
    }

    func testIndependentSpaceRecoveryRebuildsSurfaces() {
        var state = DisplaySpaceRecoveryState()

        state.activeSpaceRecoveryDidStart()

        XCTAssertEqual(
            state.activeSpaceRecoveryDidSettle(),
            .rebuildSurfaces
        )
    }

    func testDisplayDerivedSpaceRecoveryPreservesSurfaces() {
        var state = DisplaySpaceRecoveryState()

        state.displayRecoveryDidStart()
        state.activeSpaceRecoveryDidStart()

        XCTAssertEqual(
            state.activeSpaceRecoveryDidSettle(),
            .preserveSurfaces
        )
    }

    func testDisplayRecoverySuppressesAnAlreadyPendingSpaceRebuild() {
        var state = DisplaySpaceRecoveryState()

        state.activeSpaceRecoveryDidStart()
        state.displayRecoveryDidStart()
        state.displayRecoveryDidSettle()

        XCTAssertEqual(
            state.activeSpaceRecoveryDidSettle(),
            .preserveSurfaces
        )
    }

    func testIndependentSpaceRecoveryRebuildsAfterDisplaySettles() {
        var state = DisplaySpaceRecoveryState()

        state.displayRecoveryDidStart()
        state.activeSpaceRecoveryDidStart()
        XCTAssertEqual(
            state.activeSpaceRecoveryDidSettle(),
            .preserveSurfaces
        )
        state.displayRecoveryDidSettle()

        state.activeSpaceRecoveryDidStart()
        XCTAssertEqual(
            state.activeSpaceRecoveryDidSettle(),
            .rebuildSurfaces
        )
    }
}
