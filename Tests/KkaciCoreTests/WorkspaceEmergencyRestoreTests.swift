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

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")

        _ = try controller.restoreAllHiddenWindows()
        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.membership(for: 200), "1")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }
}
