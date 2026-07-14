import CoreGraphics
@testable import KkaciCore
import XCTest

class WorkspaceControllerTestCase: XCTestCase {
    let hidePoint = CGPoint(x: -1, y: -1)

    func makeController(
        _ windowSystem: FakeWindowSystem,
        displayProvider: FakeDisplayProvider? = nil,
        configStore: (any KkaciConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil,
        isConfigPersistenceEnabled: Bool = true
    ) -> WorkspaceController {
        WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider ?? FakeDisplayProvider(point: hidePoint),
            configStore: configStore,
            recordStore: recordStore,
            isConfigPersistenceEnabled: isConfigPersistenceEnabled
        )
    }

    func twoDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), isMain: true),
                DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), isMain: false)
            ]
        )
    }

    func differentSizedDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), isMain: true),
                DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 500, height: 500), isMain: false)
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

        _ = controller.discoverWindows()
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

        _ = controller.discoverWindows()
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

    func testSwitchIgnoresFailureFromAnUnrelatedInactiveWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
            .window(id: 300, title: "Three")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")
        windowSystem.frameWriteFailures.insert(300)

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(controller.activeWorkspace, "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(controller.isHiddenByWorkspace(300))
    }

    func testSwitchFailsWhenPreviousWorkspaceWindowCannotBeHidden() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Source"),
            .window(id: 200, title: "Target")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.frameWriteFailures.insert(100)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "2"))
        XCTAssertEqual(controller.activeWorkspace, "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
    }

    func testFailedSwitchRestoresSourceWindowsHiddenBeforeTheFailure() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Focused source"),
            .window(id: 101, title: "Other source"),
            .window(id: 200, title: "Target")
        ])
        let controller = makeController(windowSystem)
        let sourceFrame = try XCTUnwrap(windowSystem.frames[101])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(101, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindow = 100
        windowSystem.frameWriteFailures.insert(100)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "2"))

        XCTAssertEqual(controller.activeWorkspace, "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(101))
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.frames[101], sourceFrame)
        XCTAssertEqual(windowSystem.focusedWindow, 100)
        XCTAssertEqual(controller.currentFocusedWindowID(), 100)
    }

    func testNewWindowsAreAutoAssignedToCurrentWorkspaceAfterBaseline() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        let result = controller.discoverWindows()

        XCTAssertEqual(result.sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(controller.membership(for: 200), "3")
    }

    func testCurrentWindowsDoesNotDiscoverOrAssignNewWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        windowSystem.refreshCount = 0
        let windows = controller.currentWindows()

        XCTAssertEqual(windows.map(\.id), [100])
        XCTAssertEqual(windowSystem.refreshCount, 0)
        XCTAssertNil(controller.membership(for: 200))
    }

    func testRuntimeSnapshotQueriesDoNotReadLiveFocusOrDisplays() throws {
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let displayProvider = FakeDisplayProvider()
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        windowSystem.focusedWindow = 100

        _ = controller.discoverWindows()
        let displayQueryCount = displayProvider.displayQueryCount
        windowSystem.focusedWindow = nil
        displayProvider.snapshots = []

        XCTAssertEqual(controller.currentFocusedWindowID(), 100)
        XCTAssertEqual(controller.monitorSlots.map(\.display.id), [1])
        XCTAssertEqual(displayProvider.displayQueryCount, displayQueryCount)

        _ = try controller.handleWindowSetChanged()

        XCTAssertNil(controller.currentFocusedWindowID())
        XCTAssertTrue(controller.monitorSlots.isEmpty)
    }

    func testWindowSetChangedDiscoversAndAssignsNewWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        _ = try controller.switchWorkspace(to: "3")
        windowSystem.windows.append(.window(id: 200, title: "New"))

        let sync = try controller.handleWindowSetChanged().sync

        XCTAssertEqual(sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(controller.currentWindows().map(\.id), [100, 200])
        XCTAssertEqual(controller.membership(for: 200), "3")
    }

    func testExternalFocusEventRefreshesWindowStateOnce() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindow = 200
        windowSystem.refreshCount = 0

        let result = try controller.handleFocusedWindowChanged()

        XCTAssertEqual(windowSystem.refreshCount, 1)
        XCTAssertEqual(result.focusedWindowSync, .switched(windowID: 200, workspace: "2"))
    }

    func testWindowSetChangedRepairsInactiveWorkspaceVisibility() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[200])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        windowSystem.frames[200] = originalFrame
        windowSystem.positions[200] = originalFrame.origin

        let sync = try controller.handleWindowSetChanged().sync

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

        _ = controller.discoverWindows()
        try controller.assignWindow(200, to: "2")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(200))

        windowSystem.windows.removeAll { $0.id == 200 }
        let result = controller.discoverWindows()

        XCTAssertEqual(result.sync.removed, [200])
        XCTAssertNil(controller.membership(for: 200))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testRestoreFocusesAlreadyVisibleWindowWhenRequested() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        let result = try controller.restoreWindow(100, focus: true)

        XCTAssertEqual(result, .alreadyVisible)
        XCTAssertEqual(windowSystem.focusedIDs, [100])
    }

    func testRestoreHiddenWindowUsesCurrentDisplayWhenOriginalFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: .frame(x: 1400, y: 120, width: 300, height: 240))
        ])
        let controller = makeController(windowSystem, displayProvider: FakeDisplayProvider(point: hidePoint))

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertEqual(controller.workspaceFrame(for: 100), windowSystem.frames[100])
    }

    func testFocusWindowFocusesActiveWorkspaceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "1")

        try controller.focusWindow(200)

        XCTAssertEqual(windowSystem.focusedIDs, [200])
        XCTAssertEqual(controller.focusNextWindow(), .focused(100))
    }
}
