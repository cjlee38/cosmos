@testable import KkaciCore
import XCTest

final class WorkspaceMonitorMigrationTests: WorkspaceControllerTestCase {
    func testMonitorUpdateMovesWorkspaceWindowsToTheConfiguredMonitor() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)

        try controller.applyConfig(
            controller.currentConfig.assigningWorkspace(XCTUnwrap(WorkspaceID(rawValue: "1")), toMonitorSlot: 2)
        )

        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1100, y: 100, width: 300, height: 200))
        XCTAssertEqual(controller.workspaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 2)
    }

    func testReassigningHiddenWindowToAnotherMonitorReplacesItsRestoreFrame() throws {
        let initialConfig = KkaciConfig(
            workspaces: workspaceConfigs(["1", "2", "A", "B"], displays: ["A": 2, "B": 2]),
            shortcuts: KkaciConfig.default.shortcuts
        )
        let store = InMemoryWorkspaceConfigStore()
        try store.save(initialConfig)
        let recordStore = InMemoryHiddenWindowRecordStore()
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 7, frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store,
            recordStore: recordStore
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(100, to: "B", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(
            recordStore.records.first?.originalFrame,
            .frame(x: 1100, y: 100, width: 300, height: 200)
        )

        _ = try controller.switchWorkspace(to: "B")

        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1100, y: 100, width: 300, height: 200))
    }

    func testResizeFailureMovesCurrentWorkspaceWindowWithItsOriginalSize() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        windowSystem.operationFailure = { operation in
            guard case .setFrame(100, _) = operation else {
                return nil
            }
            return FakeWindowSystemError.frameWrite(100)
        }

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)

        try controller.applyConfig(
            controller.currentConfig.assigningWorkspace(XCTUnwrap(WorkspaceID(rawValue: "1")), toMonitorSlot: 2)
        )

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 1050, y: 50, width: originalFrame.size.width, height: originalFrame.size.height)
        )
        XCTAssertEqual(controller.workspaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 2)
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(Set(controller.visibleWorkspaces), ["1", "2"])
    }

    func testFailedHiddenWindowReassignmentRestoresThePreviousDurableFrame() throws {
        let initialConfig = KkaciConfig(
            workspaces: workspaceConfigs(["1", "2", "B"], displays: ["B": 2]),
            shortcuts: KkaciConfig.default.shortcuts
        )
        let store = InMemoryWorkspaceConfigStore()
        try store.save(initialConfig)
        let recordStore = InMemoryHiddenWindowRecordStore()
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 7, frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store,
            recordStore: recordStore
        )
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        var failedTargetWrite = false
        windowSystem.operationFailure = { operation in
            guard case .setPosition(100, _) = operation, !failedTargetWrite else {
                return nil
            }
            failedTargetWrite = true
            return FakeWindowSystemError.frameWrite(100)
        }

        XCTAssertThrowsError(try moveWindow(100, to: "B", controller: controller, windowSystem: windowSystem))

        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(controller.workspaceFrame(for: 100), originalFrame)
        XCTAssertEqual(recordStore.records.first?.workspace, "2")
        XCTAssertEqual(recordStore.records.first?.originalFrame, originalFrame)
    }
}
