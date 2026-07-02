import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

final class WorkspaceHeadlessIntegrationTests: XCTestCase {
    private let hidePoint = CGPoint(x: -1, y: -1)

    func testShutdownRecordIsAppliedOnRestartAndInactiveWorkspaceIsHiddenAgain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.applyHiddenWindowRecordsAtStartup()
        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstRecordStore.flushPendingWrites()
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        firstController.restoreHiddenWindowsForShutdown()
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.applyHiddenWindowRecordsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondRecordStore.flushPendingWrites()

        XCTAssertTrue(startup.restored.isEmpty)
        XCTAssertEqual(startup.reassigned, [HiddenWindowRecordAssignment(windowID: 200, workspace: "2")])
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(secondSystem.positions[200], hidePoint)
        XCTAssertEqual(try secondRecordStore.loadRecords().map(\.windowID), [200])
    }

    func testEmergencyUnhideClearsRecordBeforeShutdownAndRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstRecordStore.flushPendingWrites()
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])

        let result = firstController.restoreAllHiddenWindows()
        firstController.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [200], skipped: []))
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))
        XCTAssertTrue(try firstRecordStore.loadRecords().isEmpty)

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.applyHiddenWindowRecordsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondRecordStore.flushPendingWrites()

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "1")
        XCTAssertFalse(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(secondSystem.frames[200], window200Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))
    }

    func testCrashStyleRestartRestoresCornerWindowBeforeRehidingInactiveWorkspace() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstRecordStore.flushPendingWrites()
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        let hiddenFrame = try XCTUnwrap(firstSystem.frames[200])
        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: hiddenFrame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.applyHiddenWindowRecordsAtStartup()
        XCTAssertEqual(startup.restored, [200])
        XCTAssertEqual(secondSystem.frames[200], window200Frame)

        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondRecordStore.flushPendingWrites()

        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(secondSystem.positions[200], hidePoint)
        XCTAssertEqual(try secondRecordStore.loadRecords().map(\.windowID), [200])
    }

    func testExternalFocusSyncMovesToFocusedWindowWorkspaceAndUpdatesRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let recordStore = recordStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, recordStore: recordStore)

        _ = try controller.captureUnassignedVisibleWindows(into: "1")
        try controller.assignWindow(200, to: "2")
        _ = try controller.switchWorkspace(to: "1")
        recordStore.flushPendingWrites()
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [200])

        windowSystem.focusedWindow = 200
        let result = try controller.syncWorkspaceToFocusedWindow()
        recordStore.flushPendingWrites()

        XCTAssertEqual(result, .switched(windowID: 200, workspace: "2"))
        XCTAssertEqual(controller.activeWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [100])
    }

    func testNewWindowDiscoveredOnActiveWorkspaceThenHiddenWhenSwitchingAway() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let recordStore = recordStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, recordStore: recordStore)

        _ = try controller.captureUnassignedVisibleWindows(into: "1")
        try controller.assignWindow(200, to: "2")
        _ = try controller.switchWorkspace(to: "2")

        let newWindow = WindowSnapshot.window(
            id: 300,
            title: "New",
            pid: 8,
            appName: "Chrome",
            bundleID: "com.google.Chrome"
        )
        windowSystem.windows.append(newWindow)
        windowSystem.frames[300] = try XCTUnwrap(newWindow.frame)

        let sync = try controller.applyExternalWindowSetChange()
        XCTAssertEqual(sync.autoAssigned.map(\.0), [300])
        XCTAssertEqual(controller.membership(for: 300), "2")

        _ = try controller.switchWorkspace(to: "1")
        recordStore.flushPendingWrites()

        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.positions[200], hidePoint)
        XCTAssertEqual(windowSystem.positions[300], hidePoint)
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [200, 300])
    }

    func testCreatedWorkspacePersistsAndRecordReassignsToItAfterRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "dev")
        firstRecordStore.flushPendingWrites()
        firstController.restoreHiddenWindowsForShutdown()

        let persistedConfig = try FileKkaciConfigStore(url: directory.appendingPathComponent("config.toml")).load()
        XCTAssertEqual(persistedConfig.workspaces.names, ["1", "2", "3", "dev"])
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.workspace), ["dev"])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.applyHiddenWindowRecordsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondRecordStore.flushPendingWrites()

        XCTAssertEqual(secondController.workspaces, ["1", "2", "3", "dev"])
        XCTAssertEqual(startup.reassigned, [HiddenWindowRecordAssignment(windowID: 200, workspace: "dev")])
        XCTAssertEqual(secondController.membership(for: 200), "dev")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(try secondRecordStore.loadRecords().map(\.workspace), ["dev"])
    }

    func testClosedHiddenWindowPrunesRecordBeforeRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstRecordStore.flushPendingWrites()
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])

        firstSystem.windows.removeAll { $0.id == 200 }
        _ = try firstController.applyExternalWindowSetChange()
        firstRecordStore.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))

        let secondSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes", bundleID: "com.apple.Notes"),
        ])
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.applyHiddenWindowRecordsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertTrue(try secondRecordStore.loadRecords().isEmpty)
    }

    func testEmergencyUnhideRestoresMultipleHiddenWorkspacesWithFileRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let window300 = WindowSnapshot.window(id: 300, title: "Three", pid: 9, appName: "Finder", bundleID: "com.apple.finder")
        let windowSystem = FakeWindowSystem(windows: windows() + [window300])
        let recordStore = recordStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, recordStore: recordStore)
        let window200Frame = try XCTUnwrap(windowSystem.frames[200])
        let window300Frame = try XCTUnwrap(windowSystem.frames[300])

        _ = try controller.captureUnassignedVisibleWindows(into: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")
        recordStore.flushPendingWrites()
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [200, 300])

        let result = controller.restoreAllHiddenWindows()
        controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [200, 300], skipped: []))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertFalse(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.frames[200], window200Frame)
        XCTAssertEqual(windowSystem.frames[300], window300Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))
    }

    private func makeController(
        _ windowSystem: FakeWindowSystem,
        in directory: URL,
        recordStore: FileHiddenWindowRecordStore
    ) throws -> WorkspaceController {
        let configStore = FileKkaciConfigStore(url: directory.appendingPathComponent("config.toml"))
        return WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: FakeDisplayProvider(point: hidePoint),
            configStore: configStore,
            recordStore: recordStore
        )
    }

    private func recordStore(in directory: URL) -> FileHiddenWindowRecordStore {
        FileHiddenWindowRecordStore(
            url: recordURL(in: directory),
            legacyURL: legacySnapshotURL(in: directory)
        )
    }

    private func recordURL(in directory: URL) -> URL {
        directory.appendingPathComponent("hidden-window-records.json")
    }

    private func legacySnapshotURL(in directory: URL) -> URL {
        directory.appendingPathComponent("snapshot.json")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-headless-integration-\(UUID().uuidString)", isDirectory: true)
    }

    private func windows(window200Frame: WindowFrame? = nil) -> [WindowSnapshot] {
        [
            .window(id: 100, title: "One", pid: 7, appName: "Notes", bundleID: "com.apple.Notes"),
            .window(
                id: 200,
                title: "Two",
                pid: 8,
                appName: "Chrome",
                bundleID: "com.google.Chrome",
                frame: window200Frame
            ),
        ]
    }
}
