import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceWindowFocusTests: WorkspaceControllerTestCase {
    func testMoveFocusedWindowToInactiveWorkspaceHidesItAndFocusesNextSourceWindow() throws {
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
            WindowMoveResult(windowID: 100, previousWorkspace: "1", workspace: "2", outcome: .moved)
        )
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(101))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertEqual(windowSystem.focusedIDs, [101])
    }

    func testMoveFocusedWindowRejectsWindowMovedOutOfCurrentWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        _ = try controller.moveFocusedWindow(to: "2")

        XCTAssertThrowsError(try controller.moveFocusedWindow(to: "3")) { error in
            XCTAssertEqual(error as? WorkspaceError, .windowNotInCurrentWorkspace(100, "2"))
        }
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToCurrentWorkspaceKeepsItVisible() throws {
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
                previousWorkspace: "1",
                workspace: "1",
                outcome: .alreadyInWorkspace
            )
        )
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToVisibleWorkspaceOnAnotherMonitorMovesItsFrameByRatio() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200)),
            .window(id: 101, title: "Other", frame: .frame(x: 200, y: 200, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "A"], displays: ["A": 2]),
            shortcuts: KkaciConfig.default.shortcuts
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
            WindowMoveResult(windowID: 100, previousWorkspace: "1", workspace: "A", outcome: .moved)
        )
        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 150, height: 100))
        XCTAssertEqual(controller.currentWorkspace, "A")
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToInactiveWorkspaceOnAnotherMonitorRestoresThereLater() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "A", "B"], displays: ["A": 2, "B": 2]),
            shortcuts: KkaciConfig.default.shortcuts
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
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        _ = try controller.switchWorkspace(to: "B")

        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 150, height: 100))
    }

    func testDraggedVisibleWindowToAnotherMonitorMovesMembershipToVisibleWorkspaceThere() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "A"], displays: ["A": 2]),
            shortcuts: KkaciConfig.default.shortcuts
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
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(controller.currentWorkspace, "A")
        XCTAssertEqual(
            result.sync.membershipChanges,
            [WorkspaceMembershipChange(windowID: 100, previousWorkspace: "1", workspace: "A")]
        )
    }

    func testMoveFocusedWindowToMissingWorkspaceIsNoOp() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "dev")

        XCTAssertNil(result)
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }
}

final class WorkspaceExternalFocusTests: WorkspaceControllerTestCase {
    func testLayoutChangeDoesNotFollowAWorkspaceHiddenFocusedWindow() throws {
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
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
    }

    func testFocusedWindowInOtherWorkspaceSwitchesCurrentWorkspace() throws {
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

        XCTAssertEqual(result, .switched(windowID: 200, workspace: "2"))
        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
    }

    func testFocusedWindowSyncPrefersExternallyFocusedWindowInTargetWorkspace() throws {
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

        XCTAssertEqual(result, .switched(windowID: 201, workspace: "2"))
        XCTAssertEqual(windowSystem.focusedIDs.last, 201)
    }

    func testFocusedWindowInCurrentWorkspaceDoesNotSwitch() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .alreadyActive(windowID: 100, workspace: "1"))
        XCTAssertEqual(controller.currentWorkspace, "1")
    }

    func testVisibleFocusedWindowIsAssignedBeforeFocusSync() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        windowSystem.focusedWindow = 100

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .alreadyActive(windowID: 100, workspace: "1"))
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.currentWorkspace, "1")
    }
}
