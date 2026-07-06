import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceWindowCycleFocusTests: WorkspaceControllerTestCase {
    func testCaptureVisibleWindowsAssignsOnlyVisibleWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two", isMinimized: true)
        ])
        let controller = makeController(windowSystem)

        _ = try controller.captureVisibleWindows(into: "1")

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertNil(controller.membership(for: 200))
    }

    func testNextWindowFocusesNextWindowInActiveWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
            .window(id: 300, title: "Three")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "1")
        try controller.assignWindow(300, to: "2")
        windowSystem.focusedWindow = 100

        let result = controller.focusNextWindow()

        XCTAssertEqual(result, .focused(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
    }

    func testPreviousWindowWrapsInsideActiveWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "1")
        windowSystem.focusedWindow = 100

        let result = controller.focusPreviousWindow()

        XCTAssertEqual(result, .focused(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
    }

    func testWindowFocusCycleReportsEmptyWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        _ = try controller.switchWorkspace(to: "2")

        let result = controller.focusNextWindow()

        XCTAssertEqual(result, .noWindowsInWorkspace("2"))
    }

    func testWindowIDsByMostRecentFocusPutsFocusedWindowFirst() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
            .window(id: 300, title: "Three")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "1")
        try controller.assignWindow(300, to: "1")
        windowSystem.focusedWindow = 100

        XCTAssertEqual(controller.windowIDsByMostRecentFocus(in: "1"), [100, 300, 200])
    }

    func testMoveFocusedWindowToInactiveWorkspaceOnlyHidesMovedWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 101, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(101, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "2")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "2"))
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(101))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToCurrentWorkspaceKeepsItVisible() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "1")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "1"))
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testMoveFocusedWindowToActiveWorkspaceOnAnotherMonitorMovesItsFrameByRatio() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "a"],
                monitorSlotsByName: ["a": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "a")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "a"))
        XCTAssertEqual(controller.membership(for: 100), "a")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 150, height: 100))
    }

    func testMoveFocusedWindowToInactiveWorkspaceOnAnotherMonitorRestoresThereLater() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "a", "b"],
                monitorSlotsByName: ["a": 2, "b": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        _ = try controller.moveFocusedWindow(to: "b")

        XCTAssertEqual(controller.membership(for: 100), "b")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        _ = try controller.switchWorkspace(to: "b")

        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 150, height: 100))
    }

    func testDraggedVisibleWindowToAnotherMonitorMovesMembershipToActiveWorkspaceThere() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "a"],
                monitorSlotsByName: ["a": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.frames[100] = .frame(x: 1050, y: 50, width: 150, height: 100)

        try controller.applyExternalWindowSetChange()

        XCTAssertEqual(controller.membership(for: 100), "a")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
    }

    func testMoveFocusedWindowToMissingWorkspaceCreatesAndPersistsIt() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "dev")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "dev"))
        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "dev"])
        XCTAssertEqual(controller.membership(for: 100), "dev")
        XCTAssertEqual(store.savedConfigs.last?.workspaces.names, ["1", "2", "3", "dev"])

        let focusCount = windowSystem.focusedIDs.count
        _ = try controller.switchWorkspace(to: "1")
        XCTAssertEqual(windowSystem.focusedIDs.count, focusCount)
    }

    func testFocusedWindowInOtherWorkspaceSwitchesActiveWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindow = 200

        let result = try controller.syncWorkspaceToFocusedWindow()

        XCTAssertEqual(result, .switched(windowID: 200, workspace: "2"))
        XCTAssertEqual(controller.activeWorkspace, "2")
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

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(201, to: "2")
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindow = 201

        let result = try controller.syncWorkspaceToFocusedWindow()

        XCTAssertEqual(result, .switched(windowID: 201, workspace: "2"))
        XCTAssertEqual(windowSystem.focusedIDs.last, 201)
    }

    func testFocusedWindowInActiveWorkspaceDoesNotSwitch() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.syncWorkspaceToFocusedWindow()

        XCTAssertEqual(result, .alreadyActive(windowID: 100, workspace: "1"))
        XCTAssertEqual(controller.activeWorkspace, "1")
    }

    func testUnassignedFocusedWindowDoesNotSwitchWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        windowSystem.focusedWindow = 100

        let result = try controller.syncWorkspaceToFocusedWindow()

        XCTAssertEqual(result, .unmanagedWindow(100))
        XCTAssertEqual(controller.activeWorkspace, "1")
    }
}
