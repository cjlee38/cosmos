import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceStateTests: XCTestCase {
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
        XCTAssertEqual(state.findWorkspace("1"), "1")
        XCTAssertEqual(state.findWorkspace("2"), "2")
        XCTAssertEqual(state.findWorkspace("3"), "3")
        XCTAssertNil(state.findWorkspace("4"))
    }

    func testWorkspaceRecencyFollowsActivationOrder() {
        var state = WorkspaceState()

        state.activate("2")
        state.activate("3")

        XCTAssertEqual(state.workspaces, ["1", "2", "3"])
        XCTAssertEqual(state.workspacesByRecency, ["3", "2", "1"])
    }

    func testApplyConfigPreservesRecencyAndAppendsNewWorkspaces() {
        var state = WorkspaceState(config: KkaciConfig(workspaces: workspaceConfigs(["1", "2", "3"])))
        state.activate("2")

        state.applyConfig(KkaciConfig(workspaces: workspaceConfigs(["1", "2", "A"])))

        XCTAssertEqual(state.workspacesByRecency, ["2", "1", "A"])
    }

    func testApplyConfigReassignsRemovedWorkspaceWindowsToCurrentWorkspace() {
        var state = WorkspaceState(config: KkaciConfig(workspaces: workspaceConfigs(["1", "2", "A"])))
        state.assign(100, to: "A")
        state.activate("A")

        state.applyConfig(KkaciConfig(workspaces: workspaceConfigs(["1", "2", "3"])))

        XCTAssertEqual(state.workspaces, ["1", "2", "3"])
        XCTAssertEqual(state.currentWorkspace, "1")
        XCTAssertEqual(state.membership(for: 100), "1")
    }

    func testApplyConfigRemovesDeletedCurrentWorkspace() {
        var state = WorkspaceState(
            config: KkaciConfig(workspaces: workspaceConfigs(["1", "2"], displays: ["2": 2]))
        )

        state.applyConfig(KkaciConfig(workspaces: workspaceConfigs(["1", "3"])))

        XCTAssertEqual(state.workspaces, ["1", "3"])
        XCTAssertFalse(state.visibleWorkspaces(availableMonitorSlots: [1, 2]).contains("2"))
    }

    func testApplyConfigRemovesUnreferencedRuntimeWorkspaces() {
        var state = WorkspaceState(config: KkaciConfig(workspaces: workspaceConfigs(["1", "2", "A"])))

        state.applyConfig(KkaciConfig(workspaces: workspaceConfigs(["1", "2", "3"])))

        XCTAssertEqual(state.workspaces, ["1", "2", "3"])
        XCTAssertEqual(state.currentWorkspace, "1")
    }

    func testWorkspaceMembershipTracksAssignedWindowsWithoutOrdering() {
        var state = WorkspaceState()
        state.assign(300, to: "2")
        state.assign(100, to: "2")
        state.assign(200, to: "1")

        XCTAssertEqual(Set(state.windowIDs(in: "2")), [100, 300])
        XCTAssertEqual(Set(state.windowIDs(in: "1")), [200])
    }
}
