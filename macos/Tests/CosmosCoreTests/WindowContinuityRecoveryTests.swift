@testable import CosmosCore
import XCTest

final class WindowContinuityRecoveryTests: SpaceControllerTestCase {
    func testRemovedSourceDisplayWaitsForObservedRelocationBeforeRecovery() throws {
        let displayProvider = twoDisplayProvider()
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "A"], displays: ["A": 2]),
            switcher: CosmosConfig.default.switcher
        ))
        let originalFrame = WindowFrame.frame(x: 1100, y: 100, width: 300, height: 200)
        let relocatedFrame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "External", pid: 10, frame: originalFrame)
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            configStore: store
        )
        _ = try controller.handleWindowSetChanged()
        XCTAssertEqual(controller.membership(for: 100), "A")

        controller.beginWindowContinuityProtection()
        displayProvider.snapshots = [mainDisplay(id: 1)]
        let pending = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(pending.continuityRecovery.pendingWindowIDs, [100])
        XCTAssertEqual(controller.membership(for: 100), "A")

        windowSystem.frames[100] = relocatedFrame
        let recovered = try controller.handleWindowSetChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
        XCTAssertEqual(controller.membership(for: 100), "A")
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertEqual(controller.spaceFrame(for: 100), relocatedFrame)
    }

    func testEquivalentReplacementGeometryDoesNotWaitForFrameDiff() throws {
        let displayProvider = FakeDisplayProvider(snapshots: [mainDisplay(id: 2)])
        let frame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Same Geometry", pid: 10, frame: frame)
        ])
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()

        controller.beginWindowContinuityProtection()
        displayProvider.snapshots = [mainDisplay(id: 443)]
        let recovered = try controller.handleDisplayConfigurationChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
        XCTAssertEqual(controller.membership(for: 100), "1")
    }

    func testSameDisplayIDWithChangedGeometryWaitsForObservedRelocation() throws {
        let displayProvider = FakeDisplayProvider(snapshots: [mainDisplay(id: 1)])
        let originalFrame = WindowFrame.frame(x: 600, y: 600, width: 300, height: 200)
        let relocatedFrame = WindowFrame.frame(x: 450, y: 450, width: 240, height: 160)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Resized Display", pid: 10, frame: originalFrame)
        ])
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()

        controller.beginWindowContinuityProtection()
        displayProvider.snapshots = [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 800, height: 800),
                role: .main
            )
        ]
        let pending = try controller.handleDisplayConfigurationChanged()

        XCTAssertEqual(pending.continuityRecovery.pendingWindowIDs, [100])

        windowSystem.frames[100] = relocatedFrame
        let recovered = try controller.handleWindowSetChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
    }

    func testExpandedSourceDisplayDoesNotWaitWhenWindowFrameRemainsValid() throws {
        let displayProvider = FakeDisplayProvider(snapshots: [mainDisplay(id: 1)])
        let frame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Still Valid", pid: 10, frame: frame)
        ])
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()

        controller.beginWindowContinuityProtection()
        displayProvider.snapshots = [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1200, height: 1200),
                role: .main
            )
        ]
        let recovered = try controller.handleDisplayConfigurationChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
    }

    func testChangedObservedFrameRecoversOutsideActiveDisplays() throws {
        let displayProvider = FakeDisplayProvider(snapshots: [mainDisplay(id: 1)])
        let originalFrame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let temporaryFrame = WindowFrame.frame(x: 1400, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Temporary", pid: 10, frame: originalFrame)
        ])
        let controller = makeController(windowSystem, displayProvider: displayProvider)
        _ = try controller.handleWindowSetChanged()

        controller.beginWindowContinuityProtection()
        displayProvider.snapshots = [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1200, height: 1200),
                role: .main
            )
        ]
        windowSystem.frames[100] = temporaryFrame
        let recovered = try controller.handleDisplayConfigurationChanged()

        XCTAssertFalse(recovered.continuityRecovery.isPending)
    }

    func testExplicitProtectionPreservesMembershipWithoutDisplayIDChange() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Visible", pid: 10),
            .window(id: 200, title: "Hidden", pid: 20)
        ])
        let controller = makeController(windowSystem)
        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)

        controller.beginWindowContinuityProtection()
        windowSystem.windows = []
        let missing = try controller.handleWindowSetChanged()

        XCTAssertTrue(missing.sync.membershipChanges.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenBySpace(200))

        windowSystem.windows = [
            .window(id: 100, title: "Visible", pid: 10),
            .window(id: 200, title: "Hidden", pid: 20)
        ]
        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
    }

    func testRecoveryWithoutAnAnchorRemainsPendingAndReportsFailure() throws {
        let window = WindowSnapshot(
            id: 100,
            app: RunningAppInfo(pid: 10, name: "FakeApp"),
            title: "Frameless",
            frame: nil,
            isMinimized: false
        )
        let windowSystem = FakeWindowSystem(windows: [window])
        let controller = makeController(windowSystem)
        _ = try controller.handleWindowSetChanged()

        controller.beginWindowContinuityProtection()
        let result = try controller.handleWindowSetChanged()

        XCTAssertEqual(result.continuityRecovery.failedWindowIDs, [100])
        XCTAssertEqual(result.continuityRecovery.pendingWindowIDs, [100])
        XCTAssertEqual(controller.membership(for: 100), "1")
    }

    private func mainDisplay(id: DisplayID) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            role: .main
        )
    }
}
