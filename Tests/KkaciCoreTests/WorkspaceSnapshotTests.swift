import CoreGraphics
import Foundation
@testable import KkaciCore
import XCTest

final class WorkspaceSnapshotTests: XCTestCase {
    private let hidePoint = CGPoint(x: -1, y: -1)

    func testHideWritesHiddenWindowSnapshot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes", bundleID: "com.apple.Notes"),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore()
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")

        XCTAssertEqual(snapshotStore.snapshots, [
            HiddenWindowSnapshot(
                windowID: 100,
                pid: 7,
                bundleID: "com.apple.Notes",
                appName: "Notes",
                title: "One",
                workspace: "2",
                originalFrame: originalFrame,
                hiddenPosition: hidePoint,
                updatedAt: snapshotStore.snapshots[0].updatedAt
            ),
        ])
    }

    func testNormalRestoreRemovesHiddenWindowSnapshot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore()
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        _ = controller.listWindows()
        try controller.hideWindow(100)
        XCTAssertEqual(snapshotStore.snapshots.map(\.windowID), [100])

        _ = try controller.restoreWindow(100)

        XCTAssertTrue(snapshotStore.snapshots.isEmpty)
    }

    func testFileSnapshotStoreFlushesPendingWrites() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("snapshot.json")
        let store = FileHiddenWindowSnapshotStore(url: url)
        let snapshot = hiddenSnapshot(originalFrame: .frame(x: 120, y: 140), workspace: "2")

        store.upsertSnapshot(snapshot)
        store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.loadSnapshots().map(\.windowID), [100])

        store.removeSnapshot(windowID: 100, pid: 7)
        store.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.loadSnapshots().isEmpty)
    }

    func testEmergencyUnhideRestoresAllHiddenWindowsAndRemovesSnapshots() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
            .window(id: 300, title: "Three", pid: 7),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore()
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)
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
        XCTAssertTrue(snapshotStore.snapshots.isEmpty)
    }

    func testEmergencyUnhideSkipsClosedHiddenWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore()
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        _ = controller.listWindows()
        try controller.assignWindow(200, to: "2")
        windowSystem.windows.removeAll { $0.id == 200 }

        let result = controller.restoreAllHiddenWindows()

        XCTAssertEqual(result, RestoreAllHiddenWindowsResult(restored: [], skipped: [200]))
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(snapshotStore.snapshots.isEmpty)
    }

    func testWindowSyncRemovesSnapshotForClosedHiddenWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore()
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        _ = controller.listWindows()
        try controller.assignWindow(200, to: "2")
        XCTAssertEqual(snapshotStore.snapshots.map(\.windowID), [200])

        windowSystem.windows.removeAll { $0.id == 200 }
        _ = controller.syncWindowState()

        XCTAssertFalse(controller.isHiddenByWorkspace(200))
        XCTAssertTrue(snapshotStore.snapshots.isEmpty)
    }

    func testShutdownRestoreDoesNotRemoveHiddenWindowSnapshot() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore()
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = controller.listWindows()
        try controller.assignWindow(100, to: "2")
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertEqual(snapshotStore.snapshots.map(\.windowID), [100])
    }

    func testStartupSnapshotsRestoreCornerWindowAndReassignWorkspace() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let snapshot = hiddenSnapshot(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore(snapshots: [snapshot])
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        let result = try controller.applyWindowSnapshotsAtStartup()

        XCTAssertEqual(result.restored, [100])
        XCTAssertEqual(result.reassigned, [SnapshotWorkspaceAssignment(windowID: 100, workspace: "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(snapshotStore.snapshots.isEmpty)
    }

    func testStartupSnapshotsReassignOriginalFrameWindowWithoutRestoring() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let snapshot = hiddenSnapshot(originalFrame: originalFrame, workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: originalFrame),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore(snapshots: [snapshot])
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        let result = try controller.applyWindowSnapshotsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertEqual(result.reassigned, [SnapshotWorkspaceAssignment(windowID: 100, workspace: "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(snapshotStore.snapshots.isEmpty)
        XCTAssertFalse(windowSystem.operations.contains(.setFrame(100, originalFrame)))
    }

    func testStartupSnapshotsIgnorePidMismatch() throws {
        let snapshot = hiddenSnapshot(originalFrame: .frame(x: 120, y: 140), workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 8, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore(snapshots: [snapshot])
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        let result = try controller.applyWindowSnapshotsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.reassigned.isEmpty)
        XCTAssertEqual(result.ignored, [snapshot])
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertEqual(snapshotStore.snapshots, [snapshot])
    }

    func testStartupSnapshotsIgnoreWindowMovedAwayFromHiddenAndOriginalPosition() throws {
        let snapshot = hiddenSnapshot(originalFrame: .frame(x: 120, y: 140), workspace: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 900, y: 900)),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore(snapshots: [snapshot])
        let controller = makeController(windowSystem, snapshotStore: snapshotStore)

        let result = try controller.applyWindowSnapshotsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.reassigned.isEmpty)
        XCTAssertEqual(result.ignored, [snapshot])
        XCTAssertNil(controller.membership(for: 100))
        XCTAssertEqual(snapshotStore.snapshots, [snapshot])
    }

    func testStartupSnapshotsCreateMissingWorkspaceBeforeAssignment() throws {
        let snapshot = hiddenSnapshot(originalFrame: .frame(x: 120, y: 140), workspace: "dev")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
        ])
        let snapshotStore = InMemoryHiddenWindowSnapshotStore(snapshots: [snapshot])
        let store = InMemoryWorkspaceConfigStore()
        let controller = makeController(windowSystem, configStore: store, snapshotStore: snapshotStore)

        let result = try controller.applyWindowSnapshotsAtStartup()

        XCTAssertEqual(result.reassigned, [SnapshotWorkspaceAssignment(windowID: 100, workspace: "dev")])
        XCTAssertEqual(controller.workspaces, ["1", "2", "3", "dev"])
        XCTAssertEqual(controller.membership(for: 100), "dev")
        XCTAssertEqual(store.savedConfigs.last?.workspaces.names, ["1", "2", "3", "dev"])
    }

    private func hiddenSnapshot(originalFrame: WindowFrame, workspace: String) -> HiddenWindowSnapshot {
        HiddenWindowSnapshot(
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
        configStore: (any KkaciConfigStore)? = nil,
        snapshotStore: (any HiddenWindowSnapshotStoring)? = nil
    ) -> WorkspaceController {
        WorkspaceController(
            windowSystem: windowSystem,
            displayProvider: FakeDisplayProvider(point: hidePoint),
            configStore: configStore,
            snapshotStore: snapshotStore
        )
    }
}
