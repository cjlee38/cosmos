@testable import KkaciCore
import XCTest

final class WorkspaceEmergencyRestoreTests: WorkspaceHiddenWindowRecordTestCase {
    func testEmergencyUnhideKeepsRestoredWindowsVisibleAfterTheNextEvent() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Visible", pid: 7),
            .window(id: 200, title: "Hidden", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)

        _ = try controller.restoreAllHiddenWindows()
        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.membership(for: 200), "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testEmergencyUnhideRestoresFromLastValidStateWhenRefreshFails() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.refreshError = FakeWindowSystemError.refresh

        let result = try controller.restoreAllHiddenWindows()

        XCTAssertEqual(result.restored, [100])
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertTrue(recordStore.records.isEmpty)
    }
}
