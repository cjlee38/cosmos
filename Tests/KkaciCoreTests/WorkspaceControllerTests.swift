import CoreGraphics
@testable import KkaciCore
import XCTest

class WorkspaceControllerTestCase: XCTestCase {
    let hidePoint = CGPoint(x: -1, y: -1)

    func makeController(
        _ windowSystem: FakeWindowSystem,
        displayProvider: FakeDisplayProvider? = nil,
        configStore: (any KkaciConfigStore)? = nil,
        isConfigPersistenceEnabled: Bool = true
    ) -> WorkspaceController {
        WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider ?? FakeDisplayProvider(point: hidePoint),
            configStore: configStore,
            isConfigPersistenceEnabled: isConfigPersistenceEnabled
        )
    }

    func twoDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
                DisplaySnapshot(id: 2, frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000), isMain: false)
            ]
        )
    }

    func differentSizedDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
                DisplaySnapshot(id: 2, frame: CGRect(x: 1_000, y: 0, width: 500, height: 500), isMain: false)
            ]
        )
    }
}

final class WorkspaceControllerTests: WorkspaceControllerTestCase {
    func testSwitchHidesOtherWorkspacesAndRestoresTargetWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
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
            .window(id: 200, title: "Three")
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
            .setPosition(200, targetFrame.origin),
            .focus(200),
            .setPosition(101, hidePoint),
            .setPosition(100, hidePoint)
        ])
    }

    func testNewWindowsAreAutoAssignedToCurrentWorkspaceAfterBaseline() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        let result = controller.listWindows()

        XCTAssertEqual(result.sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(controller.membership(for: 200), "3")
    }

    func testCurrentWindowsDoesNotDiscoverOrAssignNewWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        let result = controller.currentWindows()

        XCTAssertEqual(result.windows.map(\.id), [100])
        XCTAssertTrue(result.sync.isEmpty)
        XCTAssertNil(controller.membership(for: 200))
    }

    func testWindowSetChangedDiscoversAndAssignsNewWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        let sync = try controller.applyExternalWindowSetChange()

        XCTAssertEqual(sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(controller.currentWindows().windows.map(\.id), [100, 200])
        XCTAssertEqual(controller.membership(for: 200), "3")
    }

    func testWindowSetChangedRepairsInactiveWorkspaceVisibility() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[200])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.frames[200] = originalFrame
        windowSystem.positions[200] = originalFrame.origin

        let sync = try controller.applyExternalWindowSetChange()

        XCTAssertTrue(sync.isEmpty)
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.positions[200], hidePoint)
    }

    func testClosedWindowsAreRemovedFromMembershipAndHiddenState() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
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
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        let result = try controller.restoreWindow(100, focus: true)

        XCTAssertEqual(result, .alreadyVisible)
        XCTAssertEqual(windowSystem.focusedIDs, [100])
    }

    func testRestoreHiddenWindowUsesCurrentDisplayWhenOriginalFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: .frame(x: 1_400, y: 120, width: 300, height: 240))
        ])
        let controller = makeController(windowSystem, displayProvider: FakeDisplayProvider(point: hidePoint))

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
    }

    func testFocusWindowFocusesActiveWorkspaceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "1")

        try controller.focusWindow(200)

        XCTAssertEqual(windowSystem.focusedIDs, [200])
        XCTAssertEqual(controller.focusNextWindow(), .focused(100))
    }
}

final class WorkspaceControllerMonitorAndConfigTests: WorkspaceControllerTestCase {
    func testFocusWindowRecordsFocusInTheWindowsWorkspaceWhenAnotherMonitorSlotIsActive() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary One", frame: .frame(x: 1_100, y: 100)),
            .window(id: 201, title: "Secondary Two", frame: .frame(x: 1_200, y: 100))
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

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(201, to: "2")

        try controller.focusWindow(200)

        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
        XCTAssertEqual(controller.windowIDsByMostRecentFocus(in: "2"), [200, 201])
    }

    func testFocusWindowRejectsInactiveWorkspaceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
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

        _ = controller.listWindows()
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

        _ = controller.listWindows()
        try controller.hideWindow(100)

        XCTAssertEqual(windowSystem.frames[100]?.origin, hidePoint)
        XCTAssertEqual(controller.workspaceFrame(for: 100), originalFrame)
    }

    func testAssigningWindowToInactiveWorkspaceHidesItImmediately() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
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
            .window(id: 200, title: "Two")
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

    func testSwitchingWorkspaceOnlyAffectsThatWorkspaceMonitorSlot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main One", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1_100, y: 100)),
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

        _ = controller.listWindows()
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
            .window(id: 200, title: "Secondary One", frame: .frame(x: 1_100, y: 100)),
            .window(id: 300, title: "Secondary Two", frame: .frame(x: 1_200, y: 100))
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

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")
        windowSystem.setPositionFailures.insert(300)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "3"))
        XCTAssertEqual(controller.activeWorkspace, "1")
        XCTAssertEqual(controller.activeWorkspaces, ["1", "2"])
    }

    func testBootstrapAssignsVisibleWindowsToTheActiveWorkspaceOnTheirMonitorSlot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1_100, y: 100))
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

    func testPreviousWorkspaceWrapsToLastConfiguredWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
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
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "4")

        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "4"])
        XCTAssertEqual(controller.currentConfig.workspaces.names, ["1", "2", "3", "4"])
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
            .window(id: 100, title: "One")
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

    func testFailedStartupConfigLoadUsesDefaultsAndDisablesPersistence() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = FailingLoadWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.startupConfigLoadError as? FailingLoadWorkspaceConfigStore.Error, .loadFailed)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "scratch")

        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "scratch"])
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testApplyConfigEnablesPersistenceAndKeepsReferencedRuntimeWorkspaces() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(
            windowSystem,
            configStore: store,
            isConfigPersistenceEnabled: false
        )

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "scratch")
        try controller.applyConfig(
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
            HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")
        ])
    }
}

final class WorkspaceControllerWindowCycleAndFocusTests: WorkspaceControllerTestCase {
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
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1_050, y: 50, width: 150, height: 100))
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
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1_050, y: 50, width: 150, height: 100))
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
        windowSystem.frames[100] = .frame(x: 1_050, y: 50, width: 150, height: 100)

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
