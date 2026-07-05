import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceStateTests: XCTestCase {
    func testInitialSyncUsesCurrentWindowsAsBaseline() {
        var state = WorkspaceState()

        let sync = state.sync(windows: [.window(id: 100, title: "existing")]) { _ in 1 }

        XCTAssertTrue(sync.isEmpty)
        XCTAssertNil(state.membership(for: 100))
    }

    func testNewWindowsAreAutoAssignedToActiveWorkspace() {
        var state = WorkspaceState()
        _ = state.sync(windows: [.window(id: 100, title: "existing")]) { _ in 1 }
        state.activate("3")

        let sync = state.sync(windows: [
            .window(id: 100, title: "existing"),
            .window(id: 200, title: "new")
        ]) { _ in 1 }

        XCTAssertEqual(sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(sync.autoAssigned.map(\.1), ["3"])
        XCTAssertEqual(state.membership(for: 200), "3")
    }

    func testNewWindowsAreAutoAssignedToTheActiveWorkspaceOnTheirMonitorSlot() {
        var state = WorkspaceState(workspaces: WorkspaceConfig(
            names: ["1", "2"],
            monitorSlotsByName: ["2": 2]
        ))
        _ = state.sync(windows: []) { _ in 1 }

        _ = state.sync(windows: [
            .window(id: 100, title: "main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "secondary", frame: .frame(x: 1_100, y: 100))
        ]) { frame in
            guard let frame else { return 1 }
            return frame.center.x >= 1_000 ? 2 : 1
        }

        XCTAssertEqual(state.membership(for: 100), "1")
        XCTAssertEqual(state.membership(for: 200), "2")
    }

    func testRemovedWindowsArePrunedFromMembershipHiddenStateAndMRUOrder() {
        var state = WorkspaceState()
        _ = state.sync(windows: [
            .window(id: 100, title: "first"),
            .window(id: 200, title: "second")
        ]) { _ in 1 }
        state.assign(200, to: "2")
        state.storeHiddenFrameIfNeeded(.frame(x: 20, y: 20), for: 200)
        state.recordFocus(200, in: "2")

        let sync = state.sync(windows: [.window(id: 100, title: "first")]) { _ in 1 }

        XCTAssertEqual(sync.removed, [200])
        XCTAssertNil(state.membership(for: 200))
        XCTAssertFalse(state.isHidden(200))
        XCTAssertNil(state.focusTarget(for: "2", fallback: nil))
    }

    func testRepeatedHideDoesNotOverwriteOriginalFrame() {
        var state = WorkspaceState()

        state.storeHiddenFrameIfNeeded(.frame(x: 10, y: 10), for: 100)
        state.storeHiddenFrameIfNeeded(.frame(x: 999, y: 999), for: 100)

        XCTAssertEqual(state.hiddenFrame(for: 100), .frame(x: 10, y: 10))
    }

    func testDefaultWorkspacesAreOneTwoThree() {
        var state = WorkspaceState()

        state.assign(100, to: "2")
        state.activate("3")

        XCTAssertEqual(state.workspaces, ["1", "2", "3"])
        XCTAssertTrue(state.containsWorkspace("1"))
        XCTAssertTrue(state.containsWorkspace("2"))
        XCTAssertTrue(state.containsWorkspace("3"))
        XCTAssertFalse(state.containsWorkspace("4"))
    }

    func testWorkspaceCanBeAddedAtRuntime() {
        var state = WorkspaceState()

        state.addWorkspace("4")

        XCTAssertEqual(state.workspaces, ["1", "2", "3", "4"])
        XCTAssertTrue(state.containsWorkspace("4"))
    }

    func testApplyingWorkspacesKeepsReferencedRuntimeWorkspaces() {
        var state = WorkspaceState(workspaces: WorkspaceConfig(names: ["1", "2", "scratch"]))
        state.assign(100, to: "scratch")
        state.activate("scratch")

        state.applyWorkspaces(WorkspaceConfig(names: ["1", "2", "3"]))

        XCTAssertEqual(state.workspaces, ["1", "2", "3", "scratch"])
        XCTAssertEqual(state.activeWorkspace, "scratch")
    }

    func testApplyingWorkspacesKeepsActiveWorkspaceMonitorSlotsForRuntimeWorkspaces() {
        var state = WorkspaceState(workspaces: WorkspaceConfig(
            names: ["1", "2"],
            monitorSlotsByName: ["2": 2]
        ))

        state.applyWorkspaces(WorkspaceConfig(names: ["1", "3"]))

        XCTAssertEqual(state.workspaces, ["1", "3", "2"])
        XCTAssertEqual(state.monitorSlot(for: "2"), 2)
        XCTAssertTrue(state.activeWorkspaces.contains("2"))
    }

    func testApplyingWorkspacesRemovesUnreferencedRuntimeWorkspaces() {
        var state = WorkspaceState(workspaces: WorkspaceConfig(names: ["1", "2", "scratch"]))

        state.applyWorkspaces(WorkspaceConfig(names: ["1", "2", "3"]))

        XCTAssertEqual(state.workspaces, ["1", "2", "3"])
        XCTAssertEqual(state.activeWorkspace, "1")
    }

    func testWorkspaceCycleWrapsInBothDirections() {
        var state = WorkspaceState()
        state.assign(100, to: "2")
        state.assign(200, to: "3")

        XCTAssertEqual(state.nextWorkspace(after: "1"), "2")
        XCTAssertEqual(state.nextWorkspace(after: "3"), "1")
        XCTAssertEqual(state.previousWorkspace(before: "1"), "3")
        XCTAssertEqual(state.previousWorkspace(before: "2"), "1")
    }

    func testWindowCycleUsesAssignedWindowsInWorkspace() {
        var state = WorkspaceState()
        state.assign(300, to: "2")
        state.assign(100, to: "2")
        state.assign(200, to: "1")

        XCTAssertEqual(state.windowIDs(in: "2"), [100, 300])
        XCTAssertEqual(state.nextWindow(in: "2", after: nil), 100)
        XCTAssertEqual(state.nextWindow(in: "2", after: 100), 300)
        XCTAssertEqual(state.nextWindow(in: "2", after: 300), 100)
        XCTAssertEqual(state.previousWindow(in: "2", before: 100), 300)
        XCTAssertNil(state.nextWindow(in: "9", after: nil))
    }

    func testWindowOrderUsesMostRecentFocusWithFocusedOverride() {
        var state = WorkspaceState()
        state.assign(100, to: "2")
        state.assign(200, to: "2")
        state.assign(300, to: "2")
        state.recordFocus(100, in: "2")

        XCTAssertEqual(state.windowIDsByMostRecentFocus(in: "2"), [100, 300, 200])
        XCTAssertEqual(state.windowIDsByMostRecentFocus(in: "2", currentFocused: 200), [200, 100, 300])
        XCTAssertEqual(state.windowIDsByMostRecentFocus(in: "2", currentFocused: 999), [100, 300, 200])
    }
}
