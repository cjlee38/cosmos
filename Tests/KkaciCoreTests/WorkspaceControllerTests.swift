import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceControllerTests: XCTestCase {
    private let hidePoint = CGPoint(x: -1, y: -1)

    func testSwitchHidesOtherWorkspacesAndRestoresTargetWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        _ = try controller.switchWorkspace(to: "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.positions[200], hidePoint)

        _ = try controller.switchWorkspace(to: "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
    }

    func testSwitchRestoresAndFocusesTargetBeforeHidingPreviousWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 101, title: "Two"),
            .window(id: 200, title: "Three"),
        ])
        let controller = makeController(windowSystem)
        let targetFrame = try XCTUnwrap(windowSystem.frames[200])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(101, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindow = 100
        windowSystem.operations.removeAll()
        windowSystem.refreshCount = 0

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(windowSystem.refreshCount, 1)
        XCTAssertEqual(windowSystem.operations, [
            .refresh,
            .setFrame(200, targetFrame),
            .focus(200),
            .setPosition(101, hidePoint),
            .setPosition(100, hidePoint),
        ])
    }

    func testNewWindowsAreAutoAssignedToCurrentWorkspaceAfterBaseline() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        let result = controller.listWindows()

        XCTAssertEqual(result.sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(controller.membership(for: 200), "3")
    }

    func testClosedWindowsAreRemovedFromMembershipAndHiddenState() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(200, to: "2")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(200))

        windowSystem.windows.removeAll { $0.id == 200 }
        let result = controller.listWindows()

        XCTAssertEqual(result.sync.removed, [200])
        XCTAssertNil(controller.membership(for: 200))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testRestoreFocusesAlreadyVisibleWindowWhenRequested() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        let result = try controller.restoreWindow(100, focus: true)

        XCTAssertEqual(result, .alreadyVisible)
        XCTAssertEqual(windowSystem.focusedIDs, [100])
    }

    func testRepeatedHideRestoresOriginalFrame() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.listWindows()
        try controller.hideWindow(100)
        try controller.hideWindow(100)
        let result = try controller.restoreWindow(100)

        XCTAssertEqual(result, .restored)
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testAssigningWindowToInactiveWorkspaceHidesItImmediately() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")

        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
    }

    func testNextWorkspaceSwitchesThroughConfiguredWorkspaces() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        let result = try controller.switchToNextWorkspace()

        XCTAssertEqual(result.workspace, "2")
        XCTAssertEqual(controller.activeWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testPreviousWorkspaceWrapsToLastConfiguredWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        let result = try controller.switchToPreviousWorkspace()

        XCTAssertEqual(result.workspace, "3")
        XCTAssertEqual(controller.activeWorkspace, "3")
    }

    func testMissingWorkspaceIsCreatedAndPersisted() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "4")

        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "4"])
        XCTAssertEqual(controller.membership(for: 100), "4")
        XCTAssertEqual(store.savedConfigs.last?.workspaces.names, ["1", "2", "3", "4"])
        XCTAssertEqual(store.savedConfigs.last?.bindings, KkaciConfig.default.bindings)
    }

    func testSwitchingToMissingWorkspaceCreatesIt() throws {
        let windowSystem = FakeWindowSystem(windows: [])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = try controller.switchWorkspace(to: "dev")

        XCTAssertEqual(controller.activeWorkspace, "dev")
        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "dev"])
        XCTAssertEqual(store.savedConfigs.last?.workspaces.names, ["1", "2", "3", "dev"])
        XCTAssertEqual(store.savedConfigs.last?.bindings, KkaciConfig.default.bindings)
    }

    func testDisabledConfigPersistenceDoesNotSaveCreatedWorkspaces() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(
            windowSystem,
            configStore: store,
            isConfigPersistenceEnabled: false
        )

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "scratch")

        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "scratch"])
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testApplyConfigEnablesPersistenceAndKeepsReferencedRuntimeWorkspaces() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(
            windowSystem,
            configStore: store,
            isConfigPersistenceEnabled: false
        )

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "scratch")
        controller.applyConfig(
            KkaciConfig(
                workspaces: WorkspaceConfig(names: ["1", "2", "3"]),
                bindings: [HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")]
            ),
            enablePersistence: true
        )
        try controller.createWorkspace(named: "dev")

        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "scratch", "dev"])
        XCTAssertEqual(store.savedConfigs.last?.workspaces.names, ["1", "2", "3", "scratch", "dev"])
        XCTAssertEqual(store.savedConfigs.last?.bindings, [
            HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev"),
        ])
    }

    func testCaptureVisibleWindowsAssignsOnlyVisibleWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two", isMinimized: true),
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
            .window(id: 300, title: "Three"),
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
            .window(id: 200, title: "Two"),
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
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        _ = try controller.switchWorkspace(to: "2")

        let result = controller.focusNextWindow()

        XCTAssertEqual(result, .noWindowsInWorkspace("2"))
    }

    func testMoveFocusedWindowToInactiveWorkspaceHidesItAndFocusesReplacement() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 101, title: "Two"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(101, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "2")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "2", replacementFocus: .focused(101)))
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertEqual(windowSystem.focusedIDs.last, 101)
    }

    func testMoveFocusedWindowToCurrentWorkspaceKeepsItVisible() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "1")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "1", replacementFocus: nil))
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.focusedIDs.last, 100)
    }

    func testMoveFocusedWindowToMissingWorkspaceCreatesAndPersistsIt() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.focusedWindow = 100

        let result = try controller.moveFocusedWindow(to: "dev")

        XCTAssertEqual(result, WindowMoveResult(windowID: 100, workspace: "dev", replacementFocus: .noWindowsInWorkspace("1")))
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
            .window(id: 200, title: "Two"),
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
            .window(id: 201, title: "Three"),
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
            .window(id: 100, title: "One"),
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
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        windowSystem.focusedWindow = 100

        let result = try controller.syncWorkspaceToFocusedWindow()

        XCTAssertEqual(result, .unmanagedWindow(100))
        XCTAssertEqual(controller.activeWorkspace, "1")
    }

    private func makeController(
        _ windowSystem: FakeWindowSystem,
        configStore: (any KkaciConfigStore)? = nil,
        isConfigPersistenceEnabled: Bool = true
    ) -> WorkspaceController {
        WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: FakeDisplayProvider(point: hidePoint),
            configStore: configStore,
            isConfigPersistenceEnabled: isConfigPersistenceEnabled
        )
    }
}
