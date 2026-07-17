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

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")

        try controller.updateWorkspaceMonitor("1", monitorSlot: 2)

        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1100, y: 100, width: 300, height: 200))
        XCTAssertEqual(controller.workspaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(controller.monitorSlot(for: "1"), 2)
    }

    func testReassigningHiddenWindowToAnotherMonitorReplacesItsRestoreFrame() throws {
        let initialConfig = KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2", "a", "b"],
                monitorSlotsByName: ["a": 2, "b": 2]
            ),
            bindings: KkaciConfig.default.bindings
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

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        try controller.assignWindow(100, to: "b")

        XCTAssertEqual(
            recordStore.records.first?.originalFrame,
            .frame(x: 1100, y: 100, width: 300, height: 200)
        )

        _ = try controller.switchWorkspace(to: "b")

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

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")

        try controller.updateWorkspaceMonitor("1", monitorSlot: 2)

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 1050, y: 50, width: originalFrame.size.width, height: originalFrame.size.height)
        )
        XCTAssertEqual(controller.workspaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(controller.monitorSlot(for: "1"), 2)
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(Set(controller.visibleWorkspaces), ["1", "2"])
    }

    func testFailedHiddenWindowReassignmentRestoresThePreviousDurableFrame() throws {
        let initialConfig = KkaciConfig(
            workspaces: WorkspaceConfig(
                names: ["1", "2", "b"],
                monitorSlotsByName: ["b": 2]
            ),
            bindings: KkaciConfig.default.bindings
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

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        var failedTargetWrite = false
        windowSystem.operationFailure = { operation in
            guard case .setPosition(100, _) = operation, !failedTargetWrite else {
                return nil
            }
            failedTargetWrite = true
            return FakeWindowSystemError.frameWrite(100)
        }

        XCTAssertThrowsError(try controller.assignWindow(100, to: "b"))

        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(controller.workspaceFrame(for: 100), originalFrame)
        XCTAssertEqual(recordStore.records.first?.workspace, "2")
        XCTAssertEqual(recordStore.records.first?.originalFrame, originalFrame)
    }
}
