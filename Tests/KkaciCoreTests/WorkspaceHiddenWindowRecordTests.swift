import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

final class WorkspaceHiddenWindowRecordTests: XCTestCase {
    private let hidePoint = CGPoint(x: -1, y: -1)

    func testHideWritesHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes", bundleID: "com.apple.Notes"),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")

        XCTAssertEqual(recordStore.records, [
            HiddenWindowRecord(
                windowID: 100,
                pid: 7,
                bundleID: "com.apple.Notes",
                appName: "Notes",
                title: "One",
                workspace: "2",
                originalFrame: originalFrame,
                hiddenPosition: hidePoint,
                updatedAt: recordStore.records[0].updatedAt
            ),
        ])
    }

    func testNormalRestoreRemovesHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.listWindows()
        try controller.hideWindow(100)
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])

        _ = try controller.restoreWindow(100)

        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testHideSetPositionFailureDoesNotKeepNewHiddenRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        windowSystem.setPositionFailures.insert(100)

        _ = controller.listWindows()

        XCTAssertThrowsError(try controller.assignWindow(100, to: "2")) { error in
            XCTAssertEqual(error as? FakeWindowSystemError, .setPosition(100))
        }
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertFalse(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testRestoreSetPositionFailureKeepsHiddenStateAndRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])

        windowSystem.setPositionFailures.insert(100)
        XCTAssertThrowsError(try controller.restoreWindow(100)) { error in
            XCTAssertEqual(error as? FakeWindowSystemError, .setPosition(100))
        }

        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
    }

    func testFileRecordStoreFlushesPendingWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-record-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("hidden-window-records.json")
        let store = FileHiddenWindowRecordStore(url: url)
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "2")

        store.upsertRecord(record)
        store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.loadRecords().map(\.windowID), [100])

        store.removeRecord(windowID: 100, pid: 7)
        store.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.loadRecords().isEmpty)
    }

    func testEmergencyUnhideRestoresAllHiddenWindowsAndRemovesRecords() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
            .window(id: 300, title: "Three", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let frame100 = try XCTUnwrap(windowSystem.frames[100])
        let frame200 = try XCTUnwrap(windowSystem.frames[200])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")

        let result = controller.restoreAllHiddenWindows()

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
            .window(id: 200, title: "Two", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.listWindows()
        try controller.assignWindow(200, to: "2")
        windowSystem.windows.removeAll { $0.id == 200 }

        let result = controller.restoreAllHiddenWindows()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [], skipped: [200]))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testWindowSyncRemovesRecordForClosedHiddenWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.listWindows()
        try controller.assignWindow(200, to: "2")
        XCTAssertEqual(recordStore.records.map(\.windowID), [200])

        windowSystem.windows.removeAll { $0.id == 200 }
        _ = try controller.applyExternalWindowSetChange()

        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testShutdownRestoreDoesNotRemoveHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
    }

    func testShutdownRestoreUsesCurrentDisplayWhenHiddenFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 1_400, y: 120, width: 300, height: 240)),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore()
        let controller = makeController(windowSystem, recordStore: recordStore)

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")

        controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertEqual(recordStore.records.map(\.windowID), [100])
    }

    func testStartupRecordsRestoreCornerWindowAndReassignWorkspace() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let record = hiddenRecord(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        XCTAssertEqual(result.reassigned, [HiddenWindowRecordAssignment(windowID: 100, workspace: "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(recordStore.records.isEmpty)
    }

    func testStartupRecordsRestoreOffscreenOriginalFrameInsideCurrentDisplay() throws {
        let originalFrame = WindowFrame.frame(x: 1_400, y: 120, width: 300, height: 240)
        let record = hiddenRecord(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y, width: 300, height: 240)),
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
            .window(id: 100, title: "One", pid: 7, frame: originalFrame),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let controller = makeController(windowSystem, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertEqual(result.reassigned, [HiddenWindowRecordAssignment(windowID: 100, workspace: "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(recordStore.records.isEmpty)
        XCTAssertFalse(windowSystem.operations.contains(.setPosition(100, originalFrame.origin)))
    }

    func testStartupRecordsIgnorePidMismatch() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 8, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
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
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 900, y: 900)),
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

    func testStartupRecordsCreateMissingWorkspaceBeforeAssignment() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), workspace: "dev")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
        ])
        let recordStore = InMemoryHiddenWindowRecordStore(records: [record])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store, recordStore: recordStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.reassigned, [HiddenWindowRecordAssignment(windowID: 100, workspace: "dev")])
        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "dev"])
        XCTAssertEqual(controller.membership(for: 100), "dev")
        XCTAssertEqual(store.savedConfigs.last?.workspaces.names, ["1", "2", "3", "dev"])
    }

    private func hiddenRecord(originalFrame: WindowFrame, workspace: String) -> HiddenWindowRecord {
        HiddenWindowRecord(
            windowID: 100,
            pid: 7,
            bundleID: "test.fake",
            appName: "FakeApp",
            title: "One",
            workspace: workspace,
            originalFrame: originalFrame,
            hiddenPosition: hidePoint
        )
    }

    private func makeController(
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
