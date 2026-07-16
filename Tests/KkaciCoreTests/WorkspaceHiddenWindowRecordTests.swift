import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

private enum HiddenWindowRecordTestError: Error {
    case flushFailed
}

class WorkspaceHiddenWindowRecordTestCase: XCTestCase {
    let hidePoint = CGPoint(x: -1, y: -1)

    func hiddenRecord(originalFrame: WindowFrame, workspace: String) -> HiddenWindowRecord {
        HiddenWindowRecord(
            windowID: 100,
            pid: 7,
            workspace: workspace,
            originalFrame: originalFrame,
            hiddenPosition: hidePoint
        )
    }

    func makeController(
        _ windowSystem: FakeWindowSystem,
        displayProvider: FakeDisplayProvider? = nil,
        configStore: (any KkaciConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil
    ) -> WorkspaceController {
        WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider ?? FakeDisplayProvider(point: hidePoint),
            configStore: configStore,
            recordStore: recordStore
        )
    }
}

final class WorkspaceHiddenWindowRecordTests: WorkspaceHiddenWindowRecordTestCase {
    func testHideWritesHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes")
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")

        XCTAssertEqual(recordStore.records, [
            HiddenWindowRecord(
                windowID: 100,
                pid: 7,
                workspace: "2",
                originalFrame: originalFrame,
                hiddenPosition: hidePoint,
                updatedAt: recordStore.records[0].updatedAt
            )
        ])
    }

    func testNormalRestoreRemovesHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.discoverWindows()
        try controller.hideWindow(100)
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])

        _ = try controller.restoreWindow(100)

        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testHideSetPositionFailureDoesNotKeepNewHiddenRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        windowSystem.frameWriteFailures.insert(100)

        _ = controller.discoverWindows()

        XCTAssertThrowsError(try controller.assignWindow(100, to: "2")) { error in
            XCTAssertEqual(error as? FakeWindowSystemError, .frameWrite(100))
        }
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testRestoreSetPositionFailureKeepsHiddenStateAndRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])

        windowSystem.frameWriteFailures.insert(100)
        XCTAssertThrowsError(try controller.restoreWindow(100)) { error in
            XCTAssertEqual(error as? FakeWindowSystemError, .frameWrite(100))
        }

        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
    }

    func testNormalHideDoesNotSynchronouslyFlushRecords() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")

        XCTAssertEqual(recordStore.flushCallCount, 0)
    }

    func testShutdownRestoresWindowBeforeReportingRecordFlushFailure() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        recordStore.flushError = HiddenWindowRecordTestError.flushFailed

        XCTAssertThrowsError(try controller.restoreHiddenWindowsForShutdown())
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertEqual(recordStore.flushCallCount, 1)
    }

    func testEmergencyRestoreRestoresWindowBeforeReportingRecordFlushFailure() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        recordStore.flushError = HiddenWindowRecordTestError.flushFailed

        XCTAssertThrowsError(try controller.restoreAllHiddenWindows())
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(recordStore.flushCallCount, 1)
    }

    func testEmergencyUnhideRestoresAllHiddenWindowsAndRemovesRecords() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
            .window(id: 300, title: "Three", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let frame100 = try XCTUnwrap(windowSystem.frames[100])
        let frame200 = try XCTUnwrap(windowSystem.frames[200])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")

        let result = try controller.restoreAllHiddenWindows()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [200, 300], skipped: []))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertFalse(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.frames[200], frame200)
        XCTAssertEqual(windowSystem.frames[100], frame100)
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testEmergencyUnhideSkipsClosedHiddenWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.discoverWindows()
        try controller.assignWindow(200, to: "2")
        windowSystem.windows.removeAll { $0.id == 200 }

        let result = try controller.restoreAllHiddenWindows()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [], skipped: [200]))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testWindowSyncRemovesRecordForClosedHiddenWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.discoverWindows()
        try controller.assignWindow(200, to: "2")
        XCTAssertEqual(recordStore.records.map(\.windowID), [200])

        windowSystem.windows.removeAll { $0.id == 200 }
        _ = try controller.handleWindowSetChanged()

        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testShutdownRestoreDoesNotRemoveHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
    }

    func testShutdownRestoreUsesCurrentDisplayWhenHiddenFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 1400, y: 120, width: 300, height: 240))
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.discoverWindows()
        try controller.assignWindow(100, to: "2")

        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
    }
}

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
        XCTAssertNil(controller.membership(for: 100))
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
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertEqual(recordStore.records, [record])
    }

    func testStartupRecordsRestoreMissingWorkspaceWindowIntoActiveWorkspace() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "dev")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "1")])
        XCTAssertEqual(controller.workspaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(windowSystem.frames[100], record.originalFrame)
        XCTAssertTrue(store.savedConfigs.isEmpty)
        XCTAssertTrue(recordStore.records.isEmpty)
    }
}
