@testable import KkaciCore
import XCTest

final class WorkspaceControllerConfigTests: WorkspaceControllerTestCase {
    func testBootstrapUsesConfiguredCurrentWorkspaceWhenWorkspaceOneIsAbsent() throws {
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["A", "B"]),
            switcher: KkaciConfig.default.switcher
        ))
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "Window")])
        let controller = makeController(windowSystem, configStore: store)

        _ = try controller.bootstrapWindowState()

        XCTAssertEqual(controller.currentWorkspace, "A")
        XCTAssertEqual(controller.membership(for: 100), "A")
    }

    func testMissingWorkspaceAssignmentDoesNotApplyVisibility() throws {
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(100)

        let assigned = try moveWindow(100, to: "scratch", controller: controller, windowSystem: windowSystem)

        XCTAssertNil(assigned)
        XCTAssertFalse(controller.workspaces.contains("scratch"))
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
    }

    func testMissingWorkspaceSwitchIsNoOp() throws {
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)

        let sync = try controller.switchWorkspace(to: "scratch")

        XCTAssertNil(sync)
        XCTAssertFalse(controller.workspaces.contains("scratch"))
        XCTAssertEqual(controller.currentWorkspace, "1")
    }

    func testConfigVisibilityFailureRestoresPreviousConfigAndVisibility() throws {
        let initialConfig = KkaciConfig(
            workspaces: workspaceConfigs(["1", "2"], displays: ["2": 2]),
            switcher: KkaciConfig.default.switcher
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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(200)

        XCTAssertThrowsError(try controller.applyConfig(configWithSwitchShortcut(
            "option+x",
            workspace: "1",
            workspaceIDs: ["1", "2"]
        )))

        XCTAssertEqual(controller.currentConfig, initialConfig)
        XCTAssertEqual(configuredMonitorSlot(for: "2", in: controller), 2)
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testConfigApplyReportsApplyAndRollbackFailures() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 200, title: "First"),
            .window(id: 201, title: "Second")
        ])
        let controller = makeController(windowSystem, displayProvider: twoDisplayProvider())

        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(201, to: "2", controller: controller, windowSystem: windowSystem)

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
            workspaces: workspaceConfigs(["1", "2"], displays: ["2": 2]),
            switcher: KkaciConfig.default.switcher
        ))) { error in
            guard let transactionError = error as? WorkspaceTransactionError else {
                return XCTFail("Expected WorkspaceTransactionError, got \(error)")
            }
            XCTAssertTrue(transactionError.applyError is FakeWindowSystemError)
            XCTAssertTrue(transactionError.rollbackError is FakeWindowSystemError)
        }
    }

    func testFailedStartupConfigLoadUsesDefaultsAndReportsTheError() {
        let windowSystem = FakeWindowSystem(windows: [])
        let store = FailingLoadWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.startupConfigLoadError as? FailingLoadWorkspaceConfigStore.Error, .loadFailed)
    }

    func testApplyConfigRemovesWorkspaceAndReassignsItsWindowToCurrentWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "2", "A"]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(windowSystem, configStore: store)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "A", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "A")
        try controller.applyConfig(configWithSwitchShortcut(
            "option+d",
            workspace: "3",
            workspaceIDs: ["1", "2", "3"]
        ))

        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.currentConfig.configuredShortcuts, [
            ConfiguredShortcut(key: "option+command+c", target: .centerWindow),
            ConfiguredShortcut(key: "option+d", target: .switchWorkspace("3"))
        ])
    }
}

private func configWithSwitchShortcut(
    _ shortcut: String,
    workspace: String,
    workspaceIDs: [String]
) -> KkaciConfig {
    KkaciConfig(
        workspaces: workspaceIDs.map { workspaceID in
            let id = WorkspaceID(rawValue: workspaceID)!
            return WorkspaceConfig(
                id: id,
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: id.rawValue == workspace ? shortcut : nil
                )
            )
        }
    )
}
