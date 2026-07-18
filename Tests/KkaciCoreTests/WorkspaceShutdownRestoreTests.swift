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

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(100)

        XCTAssertThrowsError(try controller.restoreHiddenWindowsForShutdown()) { error in
            XCTAssertEqual((error as? ShutdownRestoreError)?.failedWindowIDs, [100])
        }
        XCTAssertEqual(windowSystem.frames[200], originalFrame200)
    }

    func testShutdownRestoresFromLastValidStateWhenRefreshFails() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 7)
        ])
        let controller = makeController(windowSystem)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.refreshError = FakeWindowSystemError.refresh

        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testShutdownContinuesAfterDisplayLookupFailureAndFlushesRecords() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let displayProvider = FakeDisplayProvider(point: hidePoint)
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(
            windowSystem,
            displayProvider: displayProvider,
            recordStore: recordStore
        )
        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        displayProvider.displayError = FakeWindowSystemError.refresh

        XCTAssertThrowsError(try controller.restoreHiddenWindowsForShutdown()) { error in
            XCTAssertEqual((error as? ShutdownRestoreError)?.failedWindowIDs, [100, 200])
        }
        XCTAssertEqual(recordStore.flushCallCount, 1)
    }
}
