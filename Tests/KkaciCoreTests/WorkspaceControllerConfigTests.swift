@testable import KkaciCore
import XCTest

final class WorkspaceControllerConfigTests: WorkspaceControllerTestCase {
    func testMissingWorkspaceAssignmentIsNoOp() throws {
        let controller = makeController(FakeWindowSystem(windows: []))

        let assigned = try controller.assignWindow(999, to: "scratch")

        XCTAssertFalse(assigned)
        XCTAssertFalse(controller.workspaces.contains("scratch"))
    }

    func testAssignmentWithoutFocusStillFailsForExistingWorkspace() throws {
        let controller = makeController(FakeWindowSystem(windows: []))

        XCTAssertThrowsError(try controller.assignFocused(to: "1"))
    }

    func testMissingWorkspaceAssignmentDoesNotApplyVisibilityOrSaveConfig() throws {
        let store = InMemoryWorkspaceConfigStore()
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        windowSystem.frameWriteFailures.insert(100)

        let assigned = try controller.assignWindow(100, to: "scratch")

        XCTAssertFalse(assigned)
        XCTAssertFalse(controller.workspaces.contains("scratch"))
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testMissingWorkspaceSwitchIsNoOp() throws {
        let store = InMemoryWorkspaceConfigStore()
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")

        let sync = try controller.switchWorkspace(to: "scratch")

        XCTAssertNil(sync)
        XCTAssertFalse(controller.workspaces.contains("scratch"))
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testMissingWorkspaceDoesNotAttemptConfigSave() throws {
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let store = FailingSaveWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.discoverWindows()

        let assigned = try controller.assignWindow(100, to: "scratch")

        XCTAssertFalse(assigned)
        XCTAssertFalse(controller.workspaces.contains("scratch"))
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertTrue(store.saveAttempts.isEmpty)
    }

    func testConfigVisibilityFailureRestoresPreviousConfigAndVisibility() throws {
        let initialConfig = KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2"], monitorSlotsByName: ["2": 2]),
            bindings: KkaciConfig.default.bindings
        )
        let store = InMemoryWorkspaceConfigStore()
        try store.save(initialConfig)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.frameWriteFailures.insert(200)

        XCTAssertThrowsError(try controller.applyConfig(KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2"]),
            bindings: [HotKeyBinding(key: "option+x", command: "workspace", workspace: "1")]
        )))

        XCTAssertEqual(controller.currentConfig, initialConfig)
        XCTAssertEqual(controller.monitorSlot(for: "2"), 2)
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testMonitorUpdateSaveFailureRestoresRuntimeAndHiddenRecords() throws {
        let initialConfig = KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2"], monitorSlotsByName: ["2": 2]),
            bindings: KkaciConfig.default.bindings
        )
        let store = FailingSaveWorkspaceConfigStore(loadedConfig: initialConfig)
        let recordStore = InMemoryHiddenWindowRecordStore()
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let originalFrame = try XCTUnwrap(windowSystem.frames[200])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store,
            recordStore: recordStore
        )

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        XCTAssertThrowsError(try controller.updateWorkspaceMonitor("2", monitorSlot: 1)) { error in
            XCTAssertEqual(error as? FailingSaveWorkspaceConfigStore.Error, .saveFailed)
        }

        XCTAssertEqual(controller.currentConfig, initialConfig)
        XCTAssertEqual(windowSystem.frames[200], originalFrame)
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testFailedStartupLoadKeepsMonitorUpdatePersistenceDisabled() throws {
        let store = FailingLoadWorkspaceConfigStore()
        let controller = makeController(FakeWindowSystem(windows: []), configStore: store)

        try controller.updateWorkspaceMonitor("2", monitorSlot: 2)

        XCTAssertEqual(controller.monitorSlot(for: "2"), 2)
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testConfigApplyReportsApplyAndRollbackFailures() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 200, title: "First"),
            .window(id: 201, title: "Second")
        ])
        let controller = makeController(windowSystem, displayProvider: twoDisplayProvider())

        _ = controller.discoverWindows()
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(201, to: "2")

        var restoredWindowID: WindowID?
        windowSystem.operationFailure = { [hidePoint] operation in
            guard case let .setPosition(windowID, point) = operation else {
                return nil
            }
            if point != hidePoint {
                if restoredWindowID == nil {
                    restoredWindowID = windowID
                    return nil
                }
                return FakeWindowSystemError.frameWrite(windowID)
            }
            if windowID == restoredWindowID {
                return FakeWindowSystemError.frameWrite(windowID)
            }
            return nil
        }

        XCTAssertThrowsError(try controller.applyConfig(KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2"], monitorSlotsByName: ["2": 2]),
            bindings: KkaciConfig.default.bindings
        ))) { error in
            guard let transactionError = error as? WorkspaceTransactionError else {
                return XCTFail("Expected WorkspaceTransactionError, got \(error)")
            }
            XCTAssertTrue(transactionError.applyError is FakeWindowSystemError)
            XCTAssertTrue(transactionError.rollbackError is FakeWindowSystemError)
        }
    }

    func testPreviousWorkspaceWrapsToLastConfiguredWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        let result = try controller.switchToPreviousWorkspace()

        XCTAssertEqual(result.workspace, "3")
        XCTAssertEqual(controller.currentWorkspace, "3")
    }

    func testMissingWorkspaceIsNotCreatedOrPersisted() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.discoverWindows()
        let assigned = try controller.assignWindow(100, to: "4")

        XCTAssertFalse(assigned)
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testSwitchingToMissingWorkspaceDoesNotCreateIt() throws {
        let windowSystem = FakeWindowSystem(windows: [])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        let sync = try controller.switchWorkspace(to: "dev")

        XCTAssertNil(sync)
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testMissingWorkspaceNoOpDoesNotDependOnPersistenceSetting() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(
            windowSystem,
            configStore: store,
            isConfigPersistenceEnabled: false
        )

        _ = controller.discoverWindows()
        let assigned = try controller.assignWindow(100, to: "scratch")

        XCTAssertFalse(assigned)
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
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

        _ = controller.discoverWindows()
        let assigned = try controller.assignWindow(100, to: "scratch")

        XCTAssertFalse(assigned)
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertTrue(store.savedConfigs.isEmpty)
    }

    func testApplyConfigRemovesWorkspaceAndReassignsItsWindowToCurrentWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2", "scratch"]),
            bindings: KkaciConfig.default.bindings
        ))
        let controller = makeController(windowSystem, configStore: store)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "scratch")
        _ = try controller.switchWorkspace(to: "scratch")
        try controller.applyConfig(
            KkaciConfig(
                workspaces: WorkspaceConfig(names: ["1", "2", "3"]),
                bindings: [HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")]
            ),
            enablePersistence: true
        )

        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.currentConfig.bindings, [
            HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")
        ])
    }
}
