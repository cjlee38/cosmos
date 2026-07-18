import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

class WorkspaceHeadlessIntegrationTestCase: XCTestCase {
    let hidePoint = CGPoint(x: -1, y: -1)

    func makeController(
        _ windowSystem: FakeWindowSystem,
        in directory: URL,
        recordStore: FileHiddenWindowRecordStore
    ) throws -> WorkspaceController {
        let configStore = FileKkaciConfigStore(url: directory.appendingPathComponent("config.yaml"))
        let displayProvider = FakeDisplayProvider(point: hidePoint)
        return WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: displayProvider,
            configStore: configStore,
            recordStore: recordStore
        )
    }

    func recordStore(in directory: URL) -> FileHiddenWindowRecordStore {
        FileHiddenWindowRecordStore(url: recordURL(in: directory))
    }

    func recordURL(in directory: URL) -> URL {
        directory.appendingPathComponent("hidden-window-records.json")
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-headless-integration-\(UUID().uuidString)", isDirectory: true)
    }

    func windows(window200Frame: WindowFrame? = nil) -> [WindowSnapshot] {
        [
            .window(id: 100, title: "One", pid: 7, appName: "Notes"),
            .window(
                id: 200,
                title: "Two",
                pid: 8,
                appName: "Chrome",
                frame: window200Frame
            )
        ]
    }

    @discardableResult
    func moveWindow(
        _ id: WindowID,
        to workspace: String,
        controller: WorkspaceController,
        windowSystem: FakeWindowSystem
    ) throws -> WindowMoveResult? {
        let originalWorkspace = controller.currentWorkspace
        if controller.membership(for: id) == workspace {
            return nil
        }
        if let sourceWorkspace = controller.membership(for: id),
           sourceWorkspace != controller.currentWorkspace {
            _ = try controller.switchWorkspace(to: sourceWorkspace)
        }
        windowSystem.focusedWindow = id
        _ = try controller.handleFocusedWindowChanged()
        let result = try controller.moveFocusedWindow(to: workspace)
        if controller.currentWorkspace != originalWorkspace {
            _ = try controller.switchWorkspace(to: originalWorkspace)
        }
        return result
    }
}

final class WorkspaceHeadlessIntegrationTests: WorkspaceHeadlessIntegrationTestCase {
    func testShutdownRecordIsAppliedOnRestartAndInactiveWorkspaceIsHiddenAgain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstRecordStore.flushPendingWrites()
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        try firstController.restoreHiddenWindowsForShutdown()
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.bootstrapWindowState()
        try secondRecordStore.flushPendingWrites()

        XCTAssertTrue(startup.restored.isEmpty)
        assertReassigned(startup.reassigned, [(200, "2")])
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

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstRecordStore.flushPendingWrites()
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])

        let result = try firstController.restoreAllHiddenWindows()
        try firstController.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [200], unavailable: [], failed: [])
        )
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))
        XCTAssertTrue(try firstRecordStore.loadRecords().isEmpty)

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.bootstrapWindowState()
        try secondRecordStore.flushPendingWrites()

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

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstRecordStore.flushPendingWrites()
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        let hiddenFrame = try XCTUnwrap(firstSystem.frames[200])
        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: hiddenFrame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.bootstrapWindowState()
        XCTAssertEqual(startup.restored, [200])
        try secondRecordStore.flushPendingWrites()

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

        _ = try controller.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "1")
        try recordStore.flushPendingWrites()
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [200])

        windowSystem.focusedWindow = 200
        let result = try controller.handleFocusedWindowChanged().focusedWindowSync
        try recordStore.flushPendingWrites()

        XCTAssertEqual(result, .switched(windowID: 200, workspace: "2"))
        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [100])
    }

    func testNewWindowDiscoveredOnCurrentWorkspaceThenHiddenWhenSwitchingAway() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let recordStore = recordStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, recordStore: recordStore)

        _ = try controller.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "2")

        let newWindow = WindowSnapshot.window(
            id: 300,
            title: "New",
            pid: 8,
            appName: "Chrome"
        )
        windowSystem.windows.append(newWindow)
        windowSystem.frames[300] = try XCTUnwrap(newWindow.frame)

        let sync = try controller.handleWindowSetChanged().sync
        XCTAssertEqual(sync.autoAssigned.map(\.0), [300])
        XCTAssertEqual(controller.membership(for: 300), "2")

        _ = try controller.switchWorkspace(to: "1")
        try recordStore.flushPendingWrites()

        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.positions[200], hidePoint)
        XCTAssertEqual(windowSystem.positions[300], hidePoint)
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [200, 300])
    }
}

final class WorkspaceHeadlessRestartIntegrationTests: WorkspaceHeadlessIntegrationTestCase {
    func testConfiguredWorkspaceRecordReassignsToItAfterRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configStore = FileKkaciConfigStore(url: directory.appendingPathComponent("config.yaml"))
        try configStore.save(KkaciConfig(
            workspaces: workspaceConfigs(["1", "2", "3", "D"]),
            shortcuts: KkaciConfig.default.shortcuts
        ))

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "D", controller: firstController, windowSystem: firstSystem)
        try firstRecordStore.flushPendingWrites()
        try firstController.restoreHiddenWindowsForShutdown()

        let persistedConfig = try configStore.load()
        XCTAssertEqual(persistedConfig.workspaces.map(\.id), ["1", "2", "3", "D"])
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.workspace), ["D"])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.bootstrapWindowState()
        try secondRecordStore.flushPendingWrites()

        XCTAssertEqual(secondController.workspaces, ["1", "2", "3", "D"])
        assertReassigned(startup.reassigned, [(200, "D")])
        XCTAssertEqual(secondController.membership(for: 200), "D")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(try secondRecordStore.loadRecords().map(\.workspace), ["D"])
    }

    func testClosedHiddenWindowPrunesRecordBeforeRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstRecordStore = recordStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, recordStore: firstRecordStore)

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstRecordStore.flushPendingWrites()
        XCTAssertEqual(try firstRecordStore.loadRecords().map(\.windowID), [200])

        firstSystem.windows.removeAll { $0.id == 200 }
        _ = try firstController.handleWindowSetChanged()
        try firstRecordStore.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))

        let secondSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes")
        ])
        let secondRecordStore = recordStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, recordStore: secondRecordStore)

        let startup = try secondController.bootstrapWindowState()

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertTrue(try secondRecordStore.loadRecords().isEmpty)
    }

    func testEmergencyUnhideRestoresMultipleHiddenWorkspacesWithFileRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let window300 = WindowSnapshot.window(
            id: 300,
            title: "Three",
            pid: 9,
            appName: "Finder"
        )
        let windowSystem = FakeWindowSystem(windows: windows() + [window300])
        let recordStore = recordStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, recordStore: recordStore)
        let window200Frame = try XCTUnwrap(windowSystem.frames[200])
        let window300Frame = try XCTUnwrap(windowSystem.frames[300])

        _ = try controller.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(300, to: "3", controller: controller, windowSystem: windowSystem)
        try recordStore.flushPendingWrites()
        XCTAssertEqual(try recordStore.loadRecords().map(\.windowID), [200, 300])

        let result = try controller.restoreAllHiddenWindows()
        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [200, 300], unavailable: [], failed: [])
        )
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertFalse(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.frames[200], window200Frame)
        XCTAssertEqual(windowSystem.frames[300], window300Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL(in: directory).path))
    }
}
