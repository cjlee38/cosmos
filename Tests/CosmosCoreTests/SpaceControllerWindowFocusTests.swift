import CoreGraphics
@testable import CosmosCore
import XCTest

final class SpaceWindowFocusTests: SpaceControllerTestCase {
    func testMoveFocusedWindowToInactiveSpaceHidesItAndFocusesNextSourceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 101, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(101, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "2")

        XCTAssertEqual(
            result,
            WindowMoveResult(windowID: 100, previousSpace: "1", space: "2", outcome: .moved)
        )
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertFalse(controller.isHiddenBySpace(101))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertEqual(windowSystem.focusedIDs, [101])
    }

    func testMoveFocusedWindowRejectsWindowMovedOutOfCurrentSpace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        _ = try controller.moveFocusedWindow(to: "2")

        XCTAssertThrowsError(try controller.moveFocusedWindow(to: "3")) { error in
            XCTAssertEqual(error as? SpaceError, .windowNotInCurrentSpace(100, "2"))
        }
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToCurrentSpaceKeepsItVisible() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "1")

        XCTAssertEqual(
            result,
            WindowMoveResult(
                windowID: 100,
                previousSpace: "1",
                space: "1",
                outcome: .alreadyInSpace
            )
        )
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(controller.isHiddenBySpace(100))
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToVisibleSpaceOnAnotherMonitorMovesItsFrameByRatio() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200)),
            .window(id: 101, title: "Other", frame: .frame(x: 200, y: 200, width: 300, height: 200))
        ])
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(101, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "A")

        XCTAssertEqual(
            result,
            WindowMoveResult(windowID: 100, previousSpace: "1", space: "A", outcome: .moved)
        )
        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertFalse(controller.isHiddenBySpace(100))
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 150, height: 100))
        XCTAssertEqual(controller.currentSpace, "A")
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToInactiveSpaceOnAnotherMonitorRestoresThereLater() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A", "B"], displays: ["A": 2, "B": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        _ = try controller.moveFocusedWindow(to: "B")

        XCTAssertEqual(controller.membership(for: 100), "B")
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        _ = try controller.switchSpace(to: "B")

        XCTAssertFalse(controller.isHiddenBySpace(100))
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 150, height: 100))
    }

    func testDraggedVisibleWindowToAnotherMonitorMovesMembershipToVisibleSpaceThere() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100
        windowSystem.frames[100] = .frame(x: 1050, y: 50, width: 150, height: 100)

        let result = try controller.handleWindowLayoutChanged()

        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertFalse(controller.isHiddenBySpace(100))
        XCTAssertEqual(controller.currentSpace, "A")
        XCTAssertEqual(
            result.sync.membershipChanges,
            [SpaceMembershipChange(windowID: 100, previousSpace: "1", space: "A")]
        )
    }

    func testMoveFocusedWindowToMissingSpaceIsNoOp() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "dev")

        XCTAssertNil(result)
        XCTAssertEqual(controller.spaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }
}

final class SpaceExternalFocusTests: SpaceControllerTestCase {
    func testLayoutChangeDoesNotFollowASpaceHiddenFocusedWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 200

        let result = try controller.handleWindowLayoutChanged()

        XCTAssertNil(result.focusedWindowSync)
        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertTrue(controller.isHiddenBySpace(200))
    }

    func testFocusedWindowInOtherSpaceSwitchesCurrentSpace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 200

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .switched(windowID: 200, space: "2"))
        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertFalse(controller.isHiddenBySpace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
    }

    func testFocusedWindowSyncPrefersExternallyFocusedWindowInTargetSpace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
            .window(id: 201, title: "Three")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(201, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 201

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .switched(windowID: 201, space: "2"))
        XCTAssertEqual(windowSystem.focusedIDs.last, 201)
    }

    func testFocusedWindowInCurrentSpaceDoesNotSwitch() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .alreadyActive(windowID: 100, space: "1"))
        XCTAssertEqual(controller.currentSpace, "1")
    }

    func testVisibleFocusedWindowIsAssignedBeforeFocusSync() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        windowSystem.focusedWindow = 100

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .alreadyActive(windowID: 100, space: "1"))
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.currentSpace, "1")
    }
}
