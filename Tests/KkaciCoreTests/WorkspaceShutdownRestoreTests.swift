@testable import KkaciCore
import XCTest

final class WorkspaceShutdownRestoreTests: WorkspaceControllerTestCase {
    func testShutdownAttemptsEveryRestoreAndReportsFailedWindowIDs() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let controller = makeController(windowSystem)
        let originalFrame200 = try XCTUnwrap(windowSystem.frames[200])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        try controller.assignWindow(200, to: "2")
        windowSystem.frameWriteFailures.insert(100)

        XCTAssertThrowsError(try controller.restoreHiddenWindowsForShutdown()) { error in
            XCTAssertEqual((error as? ShutdownRestoreError)?.failedWindowIDs, [100])
        }
        XCTAssertEqual(windowSystem.frames[200], originalFrame200)
    }
}
