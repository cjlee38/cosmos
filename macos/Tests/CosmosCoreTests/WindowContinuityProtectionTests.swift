import CoreGraphics
@testable import CosmosCore
import XCTest

final class WindowContinuityProtectionTests: SpaceControllerTestCase {
    func testCompleteDisplayReplacementProtectsMembershipUntilWindowsReappearTogether() throws {
        let fixture = try beginProtection(
            windows: [
                .window(id: 100, title: "Visible", pid: 10, frame: .frame(x: 100, y: 100)),
                .window(id: 200, title: "Hidden", pid: 20, frame: .frame(x: 200, y: 200))
            ],
            hiddenWindowID: 200
        )
        let controller = fixture.controller
        let windowSystem = fixture.windowSystem

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")

        windowSystem.windows = []
        let missing = try controller.handleWindowSetChanged()

        XCTAssertTrue(missing.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenBySpace(200))
        XCTAssertTrue(controller.currentWindows().isEmpty)

        windowSystem.windows = [
            .window(id: 100, title: "Visible", pid: 10, frame: .frame(x: 100, y: 100))
        ]
        let partiallyReappeared = try controller.handleWindowSetChanged()

        XCTAssertTrue(partiallyReappeared.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenBySpace(200))

        windowSystem.windows.append(
            .window(id: 200, title: "Hidden", pid: 20, frame: .frame(x: 200, y: 200))
        )
        let reappeared = try controller.handleWindowSetChanged()

        XCTAssertTrue(reappeared.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
    }

    func testProtectedWindowIsRemovedWhenItsApplicationTerminates() throws {
        let fixture = try beginProtection(windows: [
            .window(id: 100, title: "Window", pid: 10)
        ])
        let controller = fixture.controller

        let terminated = try controller.handleExternalWindowChange(ExternalWindowChange(
            terminatedApplicationPIDs: [10]
        ))

        XCTAssertEqual(terminated.sync.removed, [100])
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertTrue(controller.currentWindows().isEmpty)
    }

    func testTargetedDiscoveryContainingEveryProtectedWindowDoesNotEndProtection() throws {
        let fixture = try beginProtection(windows: [
            .window(id: 100, title: "First", pid: 10),
            .window(id: 200, title: "Second", pid: 20)
        ])
        let controller = fixture.controller
        let windowSystem = fixture.windowSystem
        let targetedDiscovery = try controller.discoverWindows(windowIDs: [100, 200])

        _ = try XCTUnwrap(controller.applyExternalWindowChange(
            ExternalWindowChange(),
            discovery: targetedDiscovery
        ))
        windowSystem.windows = []
        let missing = try controller.handleWindowSetChanged()

        XCTAssertTrue(missing.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "1")
    }

    func testReusedProtectedWindowIDIsAssignedAsANewWindow() throws {
        let fixture = try beginProtection(windows: [
            .window(id: 100, title: "Old", pid: 10)
        ])
        let controller = fixture.controller
        let windowSystem = fixture.windowSystem
        windowSystem.windows = []
        _ = try controller.handleWindowSetChanged()
        _ = try controller.switchSpace(to: "2")
        windowSystem.windows = [
            .window(id: 100, title: "New", pid: 20)
        ]

        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.membership(for: 100), "2")

        _ = try controller.handleWindowSetChanged()
        windowSystem.windows = []
        let removed = try controller.handleWindowSetChanged()

        XCTAssertEqual(removed.sync.removed, [100])
        XCTAssertNil(controller.membership(for: 100))
    }

    func testNewWindowDuringProtectionUsesNormalRemovalRules() throws {
        let fixture = try beginProtection(windows: [
            .window(id: 100, title: "Protected", pid: 10)
        ])
        let controller = fixture.controller
        let windowSystem = fixture.windowSystem
        windowSystem.windows = [
            .window(id: 200, title: "New", pid: 20)
        ]

        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "1")

        windowSystem.windows = []
        let disappeared = try controller.handleWindowSetChanged()

        XCTAssertEqual(disappeared.sync.removed, [200])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertNil(controller.membership(for: 200))
    }

    func testRejectedDisplayDiscoveryDoesNotLeaveProtectionWhenTopologyReturns() throws {
        let displayProvider = FakeDisplayProvider(snapshots: [display(id: 2)])
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 10)
        ])
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()
        displayProvider.snapshots = [display(id: 443)]
        windowSystem.discoveryApplyResults = [false]
        let rejectedDiscovery = try controller.discoverWindows(windowIDs: nil)

        let rejected = try controller.applyExternalWindowChange(
            ExternalWindowChange(displayConfigurationChanged: true),
            discovery: rejectedDiscovery
        )

        XCTAssertNil(rejected)
        displayProvider.snapshots = [display(id: 2)]
        let acceptedDiscovery = try controller.discoverWindows(windowIDs: nil)
        _ = try XCTUnwrap(controller.applyExternalWindowChange(
            ExternalWindowChange(displayConfigurationChanged: true),
            discovery: acceptedDiscovery
        ))
        XCTAssertEqual(controller.membership(for: 100), "1")

        windowSystem.windows = []
        let removed = try controller.handleWindowSetChanged()
        XCTAssertEqual(removed.sync.removed, [100])
    }

    func testDisplayRemovalWithAContinuingDisplayStillRemovesClosedWindows() throws {
        let displayProvider = twoDisplayProvider()
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Remaining"),
            .window(id: 200, title: "Closed")
        ])
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()
        displayProvider.snapshots = [display(id: 1)]
        windowSystem.windows = [.window(id: 100, title: "Remaining")]

        let result = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(result.sync.removed, [200])
        XCTAssertNil(controller.membership(for: 200))
    }

    private func beginProtection(
        windows: [WindowSnapshot],
        hiddenWindowID: WindowID? = nil
    ) throws -> ProtectionFixture {
        let displayProvider = FakeDisplayProvider(
            point: hidePoint,
            snapshots: [display(id: 2)]
        )
        let windowSystem = FakeWindowSystem(windows: windows)
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()
        if let hiddenWindowID {
            try moveWindow(hiddenWindowID, to: "2", controller: controller, windowSystem: windowSystem)
        }
        displayProvider.snapshots = [display(id: 443)]
        _ = try controller.handleDisplayConfigurationChanged()
        return ProtectionFixture(
            controller: controller,
            windowSystem: windowSystem
        )
    }

    private func display(id: DisplayID) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            role: .main
        )
    }
}

private struct ProtectionFixture {
    let controller: SpaceController
    let windowSystem: FakeWindowSystem
}
