@testable import CosmosCore
import XCTest

final class WindowContinuityRecoveryTests: SpaceControllerTestCase {
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
}
