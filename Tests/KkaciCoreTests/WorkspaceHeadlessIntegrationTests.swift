import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

final class WorkspaceHeadlessIntegrationTests: XCTestCase {
    private let hidePoint = CGPoint(x: -1, y: -1)

    func testShutdownSnapshotIsAppliedOnRestartAndInactiveWorkspaceIsHiddenAgain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSnapshotStore = snapshotStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, snapshotStore: firstSnapshotStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.applyWindowSnapshotsAtStartup()
        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstSnapshotStore.flushPendingWrites()
        XCTAssertEqual(try firstSnapshotStore.loadSnapshots().map(\.windowID), [200])
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        firstController.restoreHiddenWindowsForShutdown()
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertEqual(try firstSnapshotStore.loadSnapshots().map(\.windowID), [200])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondSnapshotStore = snapshotStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, snapshotStore: secondSnapshotStore)

        let startup = try secondController.applyWindowSnapshotsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondSnapshotStore.flushPendingWrites()

        XCTAssertTrue(startup.restored.isEmpty)
        XCTAssertEqual(startup.reassigned, [SnapshotWorkspaceAssignment(windowID: 200, workspace: "2")])
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(secondSystem.positions[200], hidePoint)
        XCTAssertEqual(try secondSnapshotStore.loadSnapshots().map(\.windowID), [200])
    }

    func testEmergencyUnhideClearsSnapshotBeforeShutdownAndRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSnapshotStore = snapshotStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, snapshotStore: firstSnapshotStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstSnapshotStore.flushPendingWrites()
        XCTAssertEqual(try firstSnapshotStore.loadSnapshots().map(\.windowID), [200])

        let result = firstController.restoreAllHiddenWindows()
        firstController.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [200], skipped: []))
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL(in: directory).path))
        XCTAssertTrue(try firstSnapshotStore.loadSnapshots().isEmpty)

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondSnapshotStore = snapshotStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, snapshotStore: secondSnapshotStore)

        let startup = try secondController.applyWindowSnapshotsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondSnapshotStore.flushPendingWrites()

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "1")
        XCTAssertFalse(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(secondSystem.frames[200], window200Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL(in: directory).path))
    }

    func testCrashStyleRestartRestoresCornerWindowBeforeRehidingInactiveWorkspace() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSnapshotStore = snapshotStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, snapshotStore: firstSnapshotStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstSnapshotStore.flushPendingWrites()
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        let hiddenFrame = try XCTUnwrap(firstSystem.frames[200])
        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: hiddenFrame))
        let secondSnapshotStore = snapshotStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, snapshotStore: secondSnapshotStore)

        let startup = try secondController.applyWindowSnapshotsAtStartup()
        XCTAssertEqual(startup.restored, [200])
        XCTAssertEqual(secondSystem.frames[200], window200Frame)

        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondSnapshotStore.flushPendingWrites()

        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(secondSystem.positions[200], hidePoint)
        XCTAssertEqual(try secondSnapshotStore.loadSnapshots().map(\.windowID), [200])
    }

    func testExternalFocusSyncMovesToFocusedWindowWorkspaceAndUpdatesSnapshots() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let snapshotStore = snapshotStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, snapshotStore: snapshotStore)

        _ = try controller.captureUnassignedVisibleWindows(into: "1")
        try controller.assignWindow(200, to: "2")
        _ = try controller.switchWorkspace(to: "1")
        snapshotStore.flushPendingWrites()
        XCTAssertEqual(try snapshotStore.loadSnapshots().map(\.windowID), [200])

        windowSystem.focusedWindow = 200
        let result = try controller.syncWorkspaceToFocusedWindow()
        snapshotStore.flushPendingWrites()

        XCTAssertEqual(result, .switched(windowID: 200, workspace: "2"))
        XCTAssertEqual(controller.activeWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
        XCTAssertEqual(try snapshotStore.loadSnapshots().map(\.windowID), [100])
    }

    func testNewWindowDiscoveredOnActiveWorkspaceThenHiddenWhenSwitchingAway() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let snapshotStore = snapshotStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, snapshotStore: snapshotStore)

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

        let sync = controller.syncWindowState()
        XCTAssertEqual(sync.autoAssigned.map(\.0), [300])
        XCTAssertEqual(controller.membership(for: 300), "2")

        _ = try controller.switchWorkspace(to: "1")
        snapshotStore.flushPendingWrites()

        XCTAssertTrue(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.positions[200], hidePoint)
        XCTAssertEqual(windowSystem.positions[300], hidePoint)
        XCTAssertEqual(try snapshotStore.loadSnapshots().map(\.windowID), [200, 300])
    }

    func testCreatedWorkspacePersistsAndSnapshotReassignsToItAfterRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSnapshotStore = snapshotStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, snapshotStore: firstSnapshotStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "dev")
        firstSnapshotStore.flushPendingWrites()
        firstController.restoreHiddenWindowsForShutdown()

        let persistedConfig = try FileKkaciConfigStore(url: directory.appendingPathComponent("config.toml")).load()
        XCTAssertEqual(persistedConfig.workspaces.names, ["1", "2", "3", "dev"])
        XCTAssertEqual(try firstSnapshotStore.loadSnapshots().map(\.workspace), ["dev"])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondSnapshotStore = snapshotStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, snapshotStore: secondSnapshotStore)

        let startup = try secondController.applyWindowSnapshotsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")
        _ = try secondController.switchWorkspace(to: secondController.activeWorkspace)
        secondSnapshotStore.flushPendingWrites()

        XCTAssertEqual(secondController.workspaces, ["1", "2", "3", "dev"])
        XCTAssertEqual(startup.reassigned, [SnapshotWorkspaceAssignment(windowID: 200, workspace: "dev")])
        XCTAssertEqual(secondController.membership(for: 200), "dev")
        XCTAssertTrue(secondController.isHiddenByWorkspace(200))
        XCTAssertEqual(try secondSnapshotStore.loadSnapshots().map(\.workspace), ["dev"])
    }

    func testClosedHiddenWindowPrunesSnapshotBeforeRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSnapshotStore = snapshotStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, snapshotStore: firstSnapshotStore)

        _ = try firstController.captureUnassignedVisibleWindows(into: "1")
        try firstController.assignWindow(200, to: "2")
        firstSnapshotStore.flushPendingWrites()
        XCTAssertEqual(try firstSnapshotStore.loadSnapshots().map(\.windowID), [200])

        firstSystem.windows.removeAll { $0.id == 200 }
        _ = firstController.syncWindowState()
        firstSnapshotStore.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL(in: directory).path))

        let secondSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes", bundleID: "com.apple.Notes"),
        ])
        let secondSnapshotStore = snapshotStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, snapshotStore: secondSnapshotStore)

        let startup = try secondController.applyWindowSnapshotsAtStartup()
        _ = try secondController.captureUnassignedVisibleWindows(into: "1")

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertTrue(try secondSnapshotStore.loadSnapshots().isEmpty)
    }

    func testEmergencyUnhideRestoresMultipleHiddenWorkspacesWithFileSnapshots() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let window300 = WindowSnapshot.window(id: 300, title: "Three", pid: 9, appName: "Finder", bundleID: "com.apple.finder")
        let windowSystem = FakeWindowSystem(windows: windows() + [window300])
        let snapshotStore = snapshotStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, snapshotStore: snapshotStore)
        let window200Frame = try XCTUnwrap(windowSystem.frames[200])
        let window300Frame = try XCTUnwrap(windowSystem.frames[300])

        _ = try controller.captureUnassignedVisibleWindows(into: "1")
        try controller.assignWindow(200, to: "2")
        try controller.assignWindow(300, to: "3")
        snapshotStore.flushPendingWrites()
        XCTAssertEqual(try snapshotStore.loadSnapshots().map(\.windowID), [200, 300])

        let result = controller.restoreAllHiddenWindows()
        controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [200, 300], skipped: []))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertFalse(controller.isHiddenByWorkspace(300))
        XCTAssertEqual(windowSystem.frames[200], window200Frame)
        XCTAssertEqual(windowSystem.frames[300], window300Frame)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL(in: directory).path))
    }

    private func makeController(
        _ windowSystem: FakeWindowSystem,
        in directory: URL,
        snapshotStore: FileHiddenWindowSnapshotStore
    ) throws -> WorkspaceController {
        let configStore = FileKkaciConfigStore(url: directory.appendingPathComponent("config.toml"))
        let config = try configStore.load()
        return WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: FakeDisplayProvider(point: hidePoint),
            config: config,
            configStore: configStore,
            snapshotStore: snapshotStore
        )
    }

    private func snapshotStore(in directory: URL) -> FileHiddenWindowSnapshotStore {
        FileHiddenWindowSnapshotStore(url: snapshotURL(in: directory))
    }

    private func snapshotURL(in directory: URL) -> URL {
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
