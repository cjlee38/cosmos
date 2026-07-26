import CoreGraphics
@testable import CosmosCore
import XCTest

final class SpaceStateTests: XCTestCase {
    func testRepeatedHideDoesNotOverwriteOriginalFrame() {
        var state = SpaceState()

        state.storeHiddenFrameIfNeeded(.frame(x: 10, y: 10), for: 100)
        state.storeHiddenFrameIfNeeded(.frame(x: 999, y: 999), for: 100)

        XCTAssertEqual(state.hiddenFrame(for: 100), .frame(x: 10, y: 10))
    }

    func testDefaultSpacesAreOneTwoThree() {
        var state = SpaceState()

        state.assign(100, to: "2")
        state.activate("3")

        XCTAssertEqual(state.spaces, ["1", "2", "3"])
        XCTAssertEqual(state.findSpace("1"), "1")
        XCTAssertEqual(state.findSpace("2"), "2")
        XCTAssertEqual(state.findSpace("3"), "3")
        XCTAssertNil(state.findSpace("4"))
    }

    func testSpaceRecencyFollowsActivationOrder() {
        var state = SpaceState()

        state.activate("2")
        state.activate("3")

        XCTAssertEqual(state.spaces, ["1", "2", "3"])
        XCTAssertEqual(state.spacesByRecency, ["3", "2", "1"])
    }

    func testApplyConfigPreservesRecencyAndAppendsNewSpaces() {
        var state = SpaceState(config: CosmosConfig(spaces: spaceConfigs(["1", "2", "3"])))
        state.activate("2")

        state.applyConfig(CosmosConfig(spaces: spaceConfigs(["1", "2", "A"])))

        XCTAssertEqual(state.spacesByRecency, ["2", "1", "A"])
    }

    func testApplyConfigReassignsRemovedSpaceWindowsToCurrentSpace() {
        var state = SpaceState(config: CosmosConfig(spaces: spaceConfigs(["1", "2", "A"])))
        state.assign(100, to: "A")
        state.activate("A")

        state.applyConfig(CosmosConfig(spaces: spaceConfigs(["1", "2", "3"])))

        XCTAssertEqual(state.spaces, ["1", "2", "3"])
        XCTAssertEqual(state.currentSpace, "1")
        XCTAssertEqual(state.membership(for: 100), "1")
    }

    func testApplyConfigRemovesDeletedCurrentSpace() {
        var state = SpaceState(
            config: CosmosConfig(spaces: spaceConfigs(["1", "2"], displays: ["2": 2]))
        )

        state.applyConfig(CosmosConfig(spaces: spaceConfigs(["1", "3"])))

        XCTAssertEqual(state.spaces, ["1", "3"])
        XCTAssertFalse(state.visibleSpaces(availableMonitorSlots: [1, 2]).contains("2"))
    }

    func testApplyConfigRemovesUnreferencedRuntimeSpaces() {
        var state = SpaceState(config: CosmosConfig(spaces: spaceConfigs(["1", "2", "A"])))

        state.applyConfig(CosmosConfig(spaces: spaceConfigs(["1", "2", "3"])))

        XCTAssertEqual(state.spaces, ["1", "2", "3"])
        XCTAssertEqual(state.currentSpace, "1")
    }

    func testSessionStateRestoresCurrentAndVisibleSpaces() {
        let state = SpaceState(
            config: CosmosConfig(
                spaces: spaceConfigs(["1", "2", "A", "B"], displays: ["A": 2, "B": 2])
            ),
            sessionState: SessionState(
                currentSpace: "2",
                visibleSpaceByMonitorSlot: [1: "2", 2: "B"]
            )
        )

        XCTAssertEqual(state.currentSpace, "2")
        XCTAssertEqual(state.spacesByRecency, ["2", "1", "A", "B"])
        XCTAssertEqual(state.visibleSpace(on: 1, availableMonitorSlots: [1, 2]), "2")
        XCTAssertEqual(state.visibleSpace(on: 2, availableMonitorSlots: [1, 2]), "B")
    }

    func testMissingSavedVisibleSpaceUsesFirstConfiguredSpaceOnThatMonitor() {
        let state = SpaceState(
            config: CosmosConfig(
                spaces: spaceConfigs(["1", "A", "B"], displays: ["A": 2, "B": 2])
            ),
            sessionState: SessionState(
                currentSpace: "1",
                visibleSpaceByMonitorSlot: [1: "1", 2: "C"]
            )
        )

        XCTAssertEqual(state.currentSpace, "1")
        XCTAssertEqual(state.visibleSpace(on: 2, availableMonitorSlots: [1, 2]), "A")
    }

    func testMissingSavedCurrentSpaceUsesFirstConfiguredSpaceOnItsMonitor() {
        let state = SpaceState(
            config: CosmosConfig(
                spaces: spaceConfigs(["1", "A", "B"], displays: ["A": 2, "B": 2])
            ),
            sessionState: SessionState(
                currentSpace: "C",
                visibleSpaceByMonitorSlot: [1: "1", 2: "C"]
            )
        )

        XCTAssertEqual(state.currentSpace, "A")
        XCTAssertEqual(state.visibleSpace(on: 2, availableMonitorSlots: [1, 2]), "A")
    }

    func testMissingSavedCurrentSpaceUsesGlobalFallbackWhenItsMonitorHasNoSpaces() {
        let state = SpaceState(
            config: CosmosConfig(spaces: spaceConfigs(["1", "2"])),
            sessionState: SessionState(
                currentSpace: "A",
                visibleSpaceByMonitorSlot: [2: "A"]
            )
        )

        XCTAssertEqual(state.currentSpace, "1")
        XCTAssertEqual(state.visibleSpace(on: 2, availableMonitorSlots: [1, 2]), "1")
    }

    func testSpaceMembershipTracksAssignedWindowsWithoutOrdering() {
        var state = SpaceState()
        state.assign(300, to: "2")
        state.assign(100, to: "2")
        state.assign(200, to: "1")

        XCTAssertEqual(Set(state.windowIDs(in: "2")), [100, 300])
        XCTAssertEqual(Set(state.windowIDs(in: "1")), [200])
    }
}
