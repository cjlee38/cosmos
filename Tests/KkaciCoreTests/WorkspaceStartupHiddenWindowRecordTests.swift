import CoreGraphics
@testable import KkaciCore
import XCTest

final class WorkspaceStartupHiddenWindowRecordTests: WorkspaceHiddenWindowRecordTestCase {
    func testStartupRecordsRestoreCornerWindowAndReassignWorkspace() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let record = hiddenRecord(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testStartupRecordsRestoreOffscreenOriginalFrameInsideCurrentDisplay() throws {
        let originalFrame = WindowFrame.frame(x: 1400, y: 120, width: 300, height: 240)
        let record = hiddenRecord(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(
                id: 100,
                title: "One",
                pid: 7,
                frame: .frame(x: hidePoint.x, y: hidePoint.y, width: 300, height: 240)
            )
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testStartupRecordsReassignOriginalFrameWindowWithoutRestoring() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let record = hiddenRecord(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: originalFrame)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        assertReassigned(result.reassigned, [(100, "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(recordStore.records.isEmpty)
        XCTAssertFalse(windowSystem.operations.contains(.setPosition(100, originalFrame.origin)))
    }

    func testStartupRecordsIgnorePidMismatch() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 8, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.reassigned.isEmpty)
        XCTAssertEqual(result.ignored, [record])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(recordStore.records, [record])
    }

    func testStartupRecordsIgnoreWindowMovedAwayFromHiddenAndOriginalPosition() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 900, y: 900))
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.reassigned.isEmpty)
        XCTAssertEqual(result.ignored, [record])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(recordStore.records, [record])
    }

    func testStartupRecordsRestoreMissingWorkspaceWindowIntoCurrentWorkspace() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "A")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "1")])
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(windowSystem.frames[100], record.originalFrame)
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testStartupRestoreFailureDoesNotBlockLaterRecords() throws {
        let first = hiddenRecord(
            windowID: 100,
            originalFrame: .frame(x: 120, y: 140),
            workspace: "2"
        )
        let second = hiddenRecord(
            windowID: 200,
            originalFrame: .frame(x: 220, y: 240),
            workspace: "2"
        )
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
            .window(id: 200, title: "Two", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        windowSystem.frameWriteFailures.insert(100)
        let recordStore = InMemoryHiddenWindowRecordStore(records: [first, second])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.failed, [100])
        XCTAssertEqual(result.restored, [200])
        assertReassigned(result.reassigned, [(200, "2")])
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
        XCTAssertEqual(controller.membership(for: 200), "2")
    }
}
