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
            workspaces: workspaceConfigs(["1", "2", "A"], displays: ["A": 2]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "A", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100
        windowSystem.focusedIDs.removeAll()

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertEqual(Set(controller.visibleWorkspaces), ["2", "A"])
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testFocusedWindowOnAnotherActiveMonitorBecomesCurrentWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "A", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "A")
        windowSystem.focusedWindow = 100

        let result = try controller.handleFocusedWindowChanged().focusedWindowSync

        XCTAssertEqual(result, .alreadyActive(windowID: 100, workspace: "1"))
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(Set(controller.visibleWorkspaces), ["1", "A"])
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
            workspaces: workspaceConfigs(["1", "2"], displays: ["2": 2]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(201, to: "2", controller: controller, windowSystem: windowSystem)

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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedIDs.removeAll()

        XCTAssertThrowsError(try controller.focusWindow(200)) { error in
            XCTAssertEqual(error as? WorkspaceError, .windowNotInVisibleWorkspace(200, "2"))
        }
        XCTAssertTrue(windowSystem.focusedIDs.isEmpty)
    }

    func testRepeatedHideRestoresOriginalFrame() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "2")
        _ = try controller.switchWorkspace(to: "1")
        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testWorkspaceFrameUsesOriginalFrameForHiddenWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: .frame(x: 40, y: 50, width: 300, height: 200))
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(windowSystem.frames[100]?.origin, hidePoint)
        XCTAssertEqual(controller.workspaceFrame(for: 100), originalFrame)
    }

    func testAssigningWindowToInactiveWorkspaceHidesItImmediately() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
    }

    func testSwitchingWorkspaceOnlyAffectsThatWorkspaceMonitorSlot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main One", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100)),
            .window(id: 300, title: "Main Two", frame: .frame(x: 200, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "2", "3"], displays: ["2": 2]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(300, to: "3", controller: controller, windowSystem: windowSystem)

        _ = try controller.switchWorkspace(to: "3")

        XCTAssertEqual(controller.currentWorkspace, "3")
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
            workspaces: workspaceConfigs(["1", "2", "3"], displays: ["2": 2, "3": 2]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(300, to: "3", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(300)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "3"))
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(controller.visibleWorkspaces, ["1", "2"])
    }

    func testBootstrapAssignsVisibleWindowsToTheVisibleWorkspaceOnTheirMonitorSlot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let store = InMemoryWorkspaceConfigStore()
        try store.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "2"], displays: ["2": 2]),
            switcher: KkaciConfig.default.switcher
        ))
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        try controller.bootstrapWindowState()

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }
}
