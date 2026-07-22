import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceDisplayTopologyTests: WorkspaceControllerTestCase {
    func testRefreshDisplayTopologyDoesNotEnumerateWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Untouched", frame: .frame(x: 100, y: 100))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider()
        )

        try controller.refreshDisplayTopology()

        XCTAssertEqual(controller.displayTopology.monitorSlots.map(\.display.id), [1, 2])
        XCTAssertEqual(windowSystem.refreshCount, 0)
        XCTAssertTrue(controller.currentWindows().isEmpty)
        XCTAssertNil(controller.membership(for: 100))
    }

    func testDisconnectedWorkspaceFallsBackToMainAndReturnsHomeWhenDisplayReconnects() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemoryWorkspaceConfigStore()
        try store.save(configWithSecondaryWorkspace())
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "A", controller: controller, windowSystem: windowSystem)

        displayProvider.snapshots = [mainDisplay()]
        _ = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(configuredMonitorSlot(for: "A", in: controller), 2)
        XCTAssertEqual(controller.effectiveMonitorSlot(for: "A"), 1)
        XCTAssertEqual(controller.visibleWorkspaces, ["1"])
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(controller.workspaceFrame(for: 200), .frame(x: 100, y: 100, width: 300, height: 200))
        XCTAssertEqual(configuredMonitorSlot(for: "A", in: controller), 2)

        displayProvider.snapshots = [mainDisplay(), secondaryDisplay()]
        _ = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(controller.effectiveMonitorSlot(for: "A"), 2)
        XCTAssertEqual(Set(controller.visibleWorkspaces), ["1", "A"])
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.frames[200], .frame(x: 1100, y: 100, width: 300, height: 200))
    }

    func testCurrentSecondaryWorkspaceStaysVisibleOnMainWhileItsDisplayIsDisconnected() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemoryWorkspaceConfigStore()
        try store.save(configWithSecondaryWorkspace())
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "A", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "A")
        displayProvider.snapshots = [mainDisplay()]

        _ = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(controller.currentWorkspace, "A")
        XCTAssertEqual(controller.visibleWorkspaces, ["A"])
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.frames[200], .frame(x: 100, y: 100))
    }

    func testMainDisplaySwapMovesWorkspaceGroupsWithTheirConfiguredRoles() throws {
        let displayProvider = FakeDisplayProvider(
            point: hidePoint,
            snapshots: [mainDisplay(), smallSecondaryDisplay()]
        )
        let store = InMemoryWorkspaceConfigStore()
        try store.save(configWithSecondaryWorkspace())
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1050, y: 50, width: 150, height: 100))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "A", controller: controller, windowSystem: windowSystem)
        displayProvider.snapshots = [
            DisplaySnapshot(id: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500), role: .main),
            DisplaySnapshot(id: 1, frame: CGRect(x: 500, y: 0, width: 1000, height: 1000), role: .extended)
        ]

        _ = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(controller.displayTopology.displays.map(\.id), [2, 1])
        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 1)
        XCTAssertEqual(configuredMonitorSlot(for: "A", in: controller), 2)
        XCTAssertEqual(windowSystem.frames[100], .frame(x: 50, y: 50, width: 150, height: 100))
        XCTAssertEqual(windowSystem.frames[200], .frame(x: 600, y: 100, width: 300, height: 200))
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "A")
    }

    func testCombinedDisplayAndFocusChangeMigratesFrameAndFollowsFocusedWorkspace() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemoryWorkspaceConfigStore()
        try store.save(configWithSecondaryWorkspace())
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100, width: 300, height: 200)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )
        _ = try controller.bootstrapWindowState()
        windowSystem.focusedWindow = 200
        displayProvider.snapshots = [mainDisplay()]

        _ = try controller.handleExternalWindowChange(ExternalWindowChange(
            displayConfigurationChanged: true,
            focusPolicy: .always
        ))

        XCTAssertEqual(controller.currentWorkspace, "A")
        XCTAssertEqual(controller.membership(for: 200), "A")
        XCTAssertEqual(windowSystem.frames[200], .frame(x: 100, y: 100, width: 300, height: 200))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    private func configWithSecondaryWorkspace() -> KkaciConfig {
        KkaciConfig(
            workspaces: workspaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: KkaciConfig.default.switcher
        )
    }

    private func mainDisplay() -> DisplaySnapshot {
        DisplaySnapshot(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            role: .main
        )
    }

    private func secondaryDisplay() -> DisplaySnapshot {
        DisplaySnapshot(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000),
            role: .extended
        )
    }

    private func smallSecondaryDisplay() -> DisplaySnapshot {
        DisplaySnapshot(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 500, height: 500),
            role: .extended
        )
    }
}
