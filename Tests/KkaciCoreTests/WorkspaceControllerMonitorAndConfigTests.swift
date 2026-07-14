import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceMultiMonitorFocusTests: WorkspaceControllerTestCase {
    func testSwitchingToEmptyWorkspaceDoesNotFocusAnotherMonitorWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2", "a"],
                monitorSlotsByName: ["a": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "a")
        windowSystem.focusedWindow = 100
        windowSystem.focusedIDs.removeAll()

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(controller.activeWorkspace, "2")
        XCTAssertEqual(Set(controller.activeWorkspaces), ["2", "a"])
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testFocusedWindowOnAnotherActiveMonitorBecomesCurrentWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
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
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "a")
        _ = try controller.switchWorkspace(to: "a")
        windowSystem.focusedWindow = 100

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .alreadyActive(windowID: 100, workspace: "1"))
        XCTAssertEqual(controller.activeWorkspace, "1")
        XCTAssertEqual(Set(controller.activeWorkspaces), ["1", "a"])
    }
}

final class WorkspaceControllerMonitorTests: WorkspaceControllerTestCase {
    func testFocusWindowOnAnotherActiveMonitorDoesNotChangeCachedZOrder() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary One", frame: .frame(x: 1100, y: 100)),
            .window(id: 201, title: "Secondary Two", frame: .frame(x: 1200, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2"],
                monitorSlotsByName: ["2": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(201, to: "2")

        try controller.focusWindow(200)

        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
        XCTAssertEqual(controller.windows(in: "2").map(\.id), [200, 201])
    }

    func testFocusWindowRejectsInactiveWorkspaceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        XCTAssertThrowsError(try controller.focusWindow(200)) { error in
            XCTAssertEqual(error as? WorkspaceError, .windowNotInActiveWorkspace(200, "2"))
        }
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testRepeatedHideRestoresOriginalFrame() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.discoverWindows()
        try controller.hideWindow(100)
        try controller.hideWindow(100)
        let result = try controller.restoreWindow(100)

        XCTAssertEqual(result, .restored)
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testWorkspaceFrameUsesOriginalFrameForHiddenWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: .frame(x: 40, y: 50, width: 300, height: 200))
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.discoverWindows()
        try controller.hideWindow(100)

        XCTAssertEqual(windowSystem.frames[100]?.origin, hidePoint)
        XCTAssertEqual(controller.workspaceFrame(for: 100), originalFrame)
    }

    func testAssigningWindowToInactiveWorkspaceHidesItImmediately() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")

        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
    }

    func testNextWorkspaceSwitchesThroughConfiguredWorkspaces() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        let result = try controller.switchToNextWorkspace()

        XCTAssertEqual(result.workspace, "2")
        XCTAssertEqual(controller.activeWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testSwitchingWorkspaceOnlyAffectsThatWorkspaceMonitorSlot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main One", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100)),
            .window(id: 300, title: "Main Two", frame: .frame(x: 200, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2", "3"],
                monitorSlotsByName: ["2": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")

        _ = try controller.switchWorkspace(to: "3")

        XCTAssertEqual(controller.activeWorkspace, "3")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertFalse(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertNotEqual(windowSystem.positions[200], hidePoint)
    }

    func testFailedSwitchRestoresPreviousMonitorSlotActivation() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary One", frame: .frame(x: 1100, y: 100)),
            .window(id: 300, title: "Secondary Two", frame: .frame(x: 1200, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2", "3"],
                monitorSlotsByName: ["2": 2, "3": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")
        windowSystem.frameWriteFailures.insert(300)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "3"))
        XCTAssertEqual(controller.activeWorkspace, "1")
        XCTAssertEqual(controller.activeWorkspaces, ["1", "2"])
    }

    func testBootstrapAssignsVisibleWindowsToTheActiveWorkspaceOnTheirMonitorSlot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2"],
                monitorSlotsByName: ["2": 2]
            ),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        try controller.bootstrapWindowState(defaultWorkspace: "1")

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }
}
