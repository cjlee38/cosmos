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

    func testNextWorkspaceSwitchesThroughFixedWorkspaces() throws {
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

    func testPreviousWorkspaceWrapsToLastFixedWorkspace() throws {
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

    func testInvalidWorkspaceIsRejected() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()

        XCTAssertThrowsError(try controller.assignWindow(100, to: "4")) { error in
            guard case WorkspaceError.invalidWorkspace("4", ["1", "2", "3"]) = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertThrowsError(try controller.switchWorkspace(to: "4"))
        XCTAssertThrowsError(try controller.captureVisibleWindows(into: "4"))
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

    private func makeController(_ windowSystem: FakeWindowSystem) -> WorkspaceController {
        WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: FakeDisplayProvider(point: hidePoint)
        )
    }
}
