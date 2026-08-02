import CoreGraphics
@testable import CosmosCore
import XCTest

final class WindowContinuityProtectionTests: SpaceControllerTestCase {}

extension WindowContinuityProtectionTests {
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

    func testFailedTargetedRecoveryKeepsProtection() throws {
        let fixture = try beginProtection(windows: [
            .window(id: 100, title: "First", pid: 10),
            .window(id: 200, title: "Second", pid: 20)
        ])
        let controller = fixture.controller
        let windowSystem = fixture.windowSystem
        windowSystem.frameWriteFailures = [100, 200]
        let targetedDiscovery = try controller.discoverWindows(windowIDs: [100, 200])

        let targeted = try XCTUnwrap(controller.applyExternalWindowChange(
            ExternalWindowChange(),
            discovery: targetedDiscovery
        ))
        XCTAssertEqual(targeted.continuityRecovery.failedWindowIDs, [100, 200])
        windowSystem.windows = []
        let missing = try controller.handleWindowSetChanged()

        XCTAssertTrue(missing.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "1")
    }

    func testRelocatedWindowKeepsMembershipUntilAnchoredFrameRecoverySucceeds() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let originalFrame = WindowFrame.frame(x: 1100, y: 100, width: 300, height: 200)
        let relocatedFrame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Protected", pid: 10, frame: originalFrame)
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )
        _ = try controller.handleWindowSetChanged()
        XCTAssertEqual(controller.membership(for: 100), "A")

        controller.beginWindowContinuityProtection()
        windowSystem.frames[100] = relocatedFrame
        windowSystem.frameWriteFailures.insert(100)

        let failedRecovery = try controller.handleWindowSetChanged()

        XCTAssertEqual(failedRecovery.continuityRecovery.failedWindowIDs, [100])
        XCTAssertEqual(failedRecovery.continuityRecovery.pendingWindowIDs, [100])
        XCTAssertNotNil(failedRecovery.continuityRecovery.failureReasonsByWindowID[100])
        XCTAssertEqual(controller.membership(for: 100), "A")

        let systemLayout = try controller.handleWindowLayoutChanged()

        XCTAssertTrue(systemLayout.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertEqual(windowSystem.frames[100], relocatedFrame)

        windowSystem.frameWriteFailures.remove(100)
        let recovered = try controller.handleWindowLayoutChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)

        windowSystem.frames[100] = relocatedFrame
        _ = try controller.handleWindowLayoutChanged()

        XCTAssertEqual(controller.membership(for: 100), "1")
    }

    func testRecoveryReleasesSuccessfulWindowsAndRetriesOnlyFailures() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let firstFrame = WindowFrame.frame(x: 1100, y: 100, width: 300, height: 200)
        let secondFrame = WindowFrame.frame(x: 1200, y: 200, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "First", pid: 10, frame: firstFrame),
            .window(id: 200, title: "Second", pid: 20, frame: secondFrame)
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )
        _ = try controller.handleWindowSetChanged()
        controller.beginWindowContinuityProtection()
        windowSystem.frames[100] = .frame(x: 100, y: 100, width: 300, height: 200)
        windowSystem.frames[200] = .frame(x: 200, y: 200, width: 300, height: 200)
        windowSystem.frameWriteFailures.insert(200)

        let partial = try controller.handleWindowSetChanged()

        XCTAssertEqual(partial.continuityRecovery.pendingWindowIDs, [200])
        XCTAssertEqual(partial.continuityRecovery.failedWindowIDs, [200])
        XCTAssertEqual(windowSystem.frames[100], firstFrame)
        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertEqual(controller.membership(for: 200), "A")

        windowSystem.operations.removeAll()
        windowSystem.frameWriteFailures.remove(200)
        let secondDiscovery = try controller.discoverWindows(windowIDs: [200])
        let completed = try XCTUnwrap(controller.applyExternalWindowChange(
            ExternalWindowChange(),
            discovery: secondDiscovery
        ))

        XCTAssertFalse(completed.continuityRecovery.isPending)
        XCTAssertEqual(windowSystem.frames[200], secondFrame)
        XCTAssertFalse(windowSystem.operations.contains { operation in
            switch operation {
            case .setPosition(100, _), .setFrame(100, _):
                true
            default:
                false
            }
        })
    }

    func testUserMoveCancelsRecoveryBeforeMonitorMembershipReconciliation() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Dragged", pid: 10, frame: .frame(x: 1100, y: 100))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )
        _ = try controller.handleWindowSetChanged()
        controller.beginWindowContinuityProtection()
        windowSystem.frames[100] = .frame(x: 100, y: 100)

        let moved = try controller.handleExternalWindowChange(ExternalWindowChange(
            userMovedWindowIDs: [100]
        ))

        XCTAssertEqual(moved.sync.membershipChanges.map(\.space), ["1"])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(moved.continuityRecovery.isPending)
    }

    func testHiddenRecoveryFailurePreservesLogicalFrameAndRecord() throws {
        let sessionStore = InMemorySessionStateStore()
        let originalFrame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Hidden", pid: 10, frame: originalFrame)
        ])
        let controller = makeController(windowSystem, sessionStateStore: sessionStore)
        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        let originalRecord = try XCTUnwrap(sessionStore.records.first)
        controller.beginWindowContinuityProtection()
        windowSystem.frames[100] = .frame(x: 700, y: 500, width: 300, height: 200)
        windowSystem.frameWriteFailures.insert(100)

        let failed = try controller.handleWindowSetChanged()

        XCTAssertEqual(failed.continuityRecovery.failedWindowIDs, [100])
        XCTAssertEqual(controller.spaceFrame(for: 100), originalFrame)
        XCTAssertEqual(sessionStore.records, [originalRecord])

        windowSystem.frameWriteFailures.remove(100)
        let recovered = try controller.handleWindowSetChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
        XCTAssertEqual(controller.spaceFrame(for: 100), originalFrame)
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
