import CoreGraphics
@testable import KkaciCore
import XCTest

class WorkspaceControllerTestCase: XCTestCase {
    let hidePoint = CGPoint(x: -1, y: -1)

    func makeController(
        _ windowSystem: FakeWindowSystem,
        displayProvider: FakeDisplayProvider? = nil,
        configStore: (any KkaciConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil
    ) -> WorkspaceController {
        let displayProvider = displayProvider ?? FakeDisplayProvider(point: hidePoint)
        return WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: displayProvider,
            configStore: configStore,
            recordStore: recordStore
        )
    }

    func twoDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
                DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), role: .extended)
            ]
        )
    }

    func differentSizedDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
                DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 500, height: 500), role: .extended)
            ]
        )
    }

    func centerTestDisplayProvider() -> FakeDisplayProvider {
        FakeDisplayProvider(
            point: hidePoint,
            snapshots: [
                DisplaySnapshot(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                    visibleFrame: CGRect(x: 0, y: 40, width: 1000, height: 960),
                    role: .main
                ),
                DisplaySnapshot(
                    id: 2,
                    frame: CGRect(x: 1000, y: 0, width: 1200, height: 900),
                    visibleFrame: CGRect(x: 1000, y: 30, width: 1200, height: 870),
                    role: .extended
                )
            ]
        )
    }

    @discardableResult
    func moveWindow(
        _ id: WindowID,
        to workspace: String,
        controller: WorkspaceController,
        windowSystem: FakeWindowSystem
    ) throws -> WindowMoveResult? {
        let originalWorkspace = controller.currentWorkspace
        if controller.membership(for: id) == nil {
            _ = try controller.bootstrapWindowState()
        }
        if controller.membership(for: id) == workspace {
            return nil
        }
        if let sourceWorkspace = controller.membership(for: id),
           sourceWorkspace != controller.currentWorkspace {
            _ = try controller.switchWorkspace(to: sourceWorkspace)
        }
        windowSystem.focusedWindow = id
        _ = try controller.handleFocusedWindowChanged()
        let result = try controller.moveFocusedWindow(to: workspace)
        if controller.currentWorkspace != originalWorkspace {
            _ = try controller.switchWorkspace(to: originalWorkspace)
        }
        return result
    }
}

final class WorkspaceControllerTests: WorkspaceControllerTestCase {
    func testCenterFocusedWindowMovesOnlyItsOriginWithinTheCurrentVisibleDisplay() throws {
        let initialFrame = WindowFrame.frame(x: 1200, y: 200, width: 400, height: 300)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: initialFrame)
        ])
        windowSystem.focusedWindow = 100
        let controller = makeController(windowSystem, displayProvider: centerTestDisplayProvider())

        let windowID = try controller.centerFocusedWindow()

        XCTAssertEqual(windowID, 100)
        XCTAssertEqual(windowSystem.positions[100], CGPoint(x: 1400, y: 315))
        XCTAssertEqual(windowSystem.frames[100]?.size, initialFrame.size)
        XCTAssertFalse(windowSystem.operations.contains { operation in
            if case .setFrame = operation { return true }
            return false
        })
    }

    func testSwitchHidesOtherWorkspacesAndRestoresTargetWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)

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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(101, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(300, to: "3", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(300)

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(controller.isHiddenByWorkspace(300))
    }

    func testSwitchFailsWhenPreviousWorkspaceWindowCannotBeHidden() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Source"),
            .window(id: 200, title: "Target")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(100)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "2"))
        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(controller.workspacesByRecency.first, "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
    }

    func testSwitchUsesFreshlyCachedFrameWhenDirectFrameReadIsUnavailable() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Source"),
            .window(id: 200, title: "Target")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.unavailableFrameReads.insert(100)

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testFailedSwitchRestoresSourceWindowsHiddenBeforeTheFailure() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Focused source"),
            .window(id: 101, title: "Other source"),
            .window(id: 200, title: "Target")
        ])
        let controller = makeController(windowSystem)
        let sourceFrame = try XCTUnwrap(windowSystem.frames[101])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(101, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindow = 100
        windowSystem.frameWriteFailures.insert(100)

        XCTAssertThrowsError(try controller.switchWorkspace(to: "2"))

        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(101))
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.frames[101], sourceFrame)
        XCTAssertEqual(windowSystem.focusedWindow, 100)
        XCTAssertEqual(controller.cachedFocusedWindowID(), 100)
    }

    func testCurrentWindowsDoesNotDiscoverOrAssignNewWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
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

        _ = try controller.handleWindowSetChanged()
        let displayQueryCount = displayProvider.displayQueryCount
        windowSystem.focusedWindow = nil
        displayProvider.snapshots = []

        XCTAssertEqual(controller.cachedFocusedWindowID(), 100)
        XCTAssertEqual(controller.displayTopology.displays.map(\.id), [1])
        XCTAssertEqual(displayProvider.displayQueryCount, displayQueryCount)

        _ = try controller.handleWindowSetChanged()

        XCTAssertNil(controller.cachedFocusedWindowID())
        XCTAssertTrue(controller.displayTopology.monitorSlots.isEmpty)
    }

    func testWindowSetChangedCachesAndAssignsNewWindowsToCurrentWorkspace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Baseline")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(200))

        windowSystem.windows.removeAll { $0.id == 200 }
        let result = try controller.handleWindowSetChanged()

        XCTAssertEqual(result.sync.removed, [200])
        XCTAssertNil(controller.membership(for: 200))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testRestoreHiddenWindowUsesCurrentDisplayWhenOriginalFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: .frame(x: 1400, y: 120, width: 300, height: 240))
        ])
        let controller = makeController(windowSystem, displayProvider: FakeDisplayProvider(point: hidePoint))

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        _ = try controller.switchWorkspace(to: "2")

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertEqual(controller.workspaceFrame(for: 100), windowSystem.frames[100])
    }

    func testFocusWindowFocusesVisibleWorkspaceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "1", controller: controller, windowSystem: windowSystem)

        try controller.focusWindow(200)

        XCTAssertEqual(windowSystem.focusedIDs, [200])
    }
}
