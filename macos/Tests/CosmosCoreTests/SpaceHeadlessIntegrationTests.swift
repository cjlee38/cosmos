import CoreGraphics
@testable import CosmosCore
import Foundation
import XCTest

class SpaceHeadlessIntegrationTestCase: XCTestCase {
    let hidePoint = CGPoint(x: -1, y: -1)

    func makeController(
        _ windowSystem: FakeWindowSystem,
        in directory: URL,
        sessionStateStore: FileSessionStateStore
    ) throws -> SpaceController {
        let configStore = FileCosmosConfigStore(url: directory.appendingPathComponent("config.yaml"))
        let displayProvider = FakeDisplayProvider(point: hidePoint)
        return SpaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: displayProvider,
            configStore: configStore,
            sessionStateStore: sessionStateStore
        )
    }

    func sessionStateStore(in directory: URL) -> FileSessionStateStore {
        FileSessionStateStore(url: sessionStateURL(in: directory))
    }

    func sessionStateURL(in directory: URL) -> URL {
        directory.appendingPathComponent("session-state.json")
    }

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-headless-integration-\(UUID().uuidString)", isDirectory: true)
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
        to space: String,
        controller: SpaceController,
        windowSystem: FakeWindowSystem
    ) throws -> WindowMoveResult? {
        let originalSpace = controller.currentSpace
        if controller.membership(for: id) == space {
            return nil
        }
        if let sourceSpace = controller.membership(for: id),
           sourceSpace != controller.currentSpace {
            _ = try controller.switchSpace(to: sourceSpace)
        }
        windowSystem.focusedWindow = id
        _ = try controller.handleFocusedWindowChanged()
        let result = try controller.moveFocusedWindow(to: space)
        if controller.currentSpace != originalSpace {
            _ = try controller.switchSpace(to: originalSpace)
        }
        return result
    }
}

final class SpaceHeadlessIntegrationTests: SpaceHeadlessIntegrationTestCase {
    func testVisibleSpaceAndWindowMembershipAreRestoredAfterRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSessionStateStore = sessionStateStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, sessionStateStore: firstSessionStateStore)

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        _ = try firstController.switchSpace(to: "2")
        try firstController.restoreHiddenWindowsForShutdown()

        let secondSystem = FakeWindowSystem(windows: windows())
        let secondSessionStateStore = sessionStateStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, sessionStateStore: secondSessionStateStore)

        _ = try secondController.bootstrapWindowState()

        XCTAssertEqual(secondController.currentSpace, "2")
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenBySpace(100))
        XCTAssertFalse(secondController.isHiddenBySpace(200))
    }

    func testShutdownRecordIsAppliedOnRestartAndInactiveSpaceIsHiddenAgain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSessionStateStore = sessionStateStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, sessionStateStore: firstSessionStateStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstSessionStateStore.flushPendingWrites()
        XCTAssertEqual(try XCTUnwrap(firstSessionStateStore.load()).hiddenWindows.map(\.windowID), [200])
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        try firstController.restoreHiddenWindowsForShutdown()
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertEqual(try XCTUnwrap(firstSessionStateStore.load()).hiddenWindows.map(\.windowID), [200])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondSessionStateStore = sessionStateStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, sessionStateStore: secondSessionStateStore)

        let startup = try secondController.bootstrapWindowState()
        try secondSessionStateStore.flushPendingWrites()

        XCTAssertTrue(startup.restored.isEmpty)
        assertReassigned(startup.reassigned, [(200, "2")])
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenBySpace(200))
        XCTAssertEqual(secondSystem.positions[200], hidePoint)
        XCTAssertEqual(try XCTUnwrap(secondSessionStateStore.load()).hiddenWindows.map(\.windowID), [200])
    }

    func testEmergencyUnhideClearsRecordBeforeShutdownAndRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSessionStateStore = sessionStateStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, sessionStateStore: firstSessionStateStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstSessionStateStore.flushPendingWrites()
        XCTAssertEqual(try XCTUnwrap(firstSessionStateStore.load()).hiddenWindows.map(\.windowID), [200])

        let result = try firstController.restoreAllHiddenWindows()
        try firstController.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [200], unavailable: [], failed: [])
        )
        XCTAssertEqual(firstSystem.frames[200], window200Frame)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionStateURL(in: directory).path))
        XCTAssertTrue(try XCTUnwrap(firstSessionStateStore.load()).hiddenWindows.isEmpty)

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondSessionStateStore = sessionStateStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, sessionStateStore: secondSessionStateStore)

        let startup = try secondController.bootstrapWindowState()
        try secondSessionStateStore.flushPendingWrites()

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "1")
        XCTAssertFalse(secondController.isHiddenBySpace(200))
        XCTAssertEqual(secondSystem.frames[200], window200Frame)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionStateURL(in: directory).path))
    }

    func testCrashStyleRestartRestoresCornerWindowBeforeRehidingInactiveSpace() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSessionStateStore = sessionStateStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, sessionStateStore: firstSessionStateStore)

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstSessionStateStore.flushPendingWrites()
        XCTAssertEqual(firstSystem.positions[200], hidePoint)

        let hiddenFrame = try XCTUnwrap(firstSystem.frames[200])
        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: hiddenFrame))
        let secondSessionStateStore = sessionStateStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, sessionStateStore: secondSessionStateStore)

        let startup = try secondController.bootstrapWindowState()
        XCTAssertEqual(startup.restored, [200])
        try secondSessionStateStore.flushPendingWrites()

        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertEqual(secondController.membership(for: 200), "2")
        XCTAssertTrue(secondController.isHiddenBySpace(200))
        XCTAssertEqual(secondSystem.positions[200], hidePoint)
        XCTAssertEqual(try XCTUnwrap(secondSessionStateStore.load()).hiddenWindows.map(\.windowID), [200])
    }

    func testExternalFocusSyncMovesToFocusedWindowSpaceAndUpdatesRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let sessionStateStore = sessionStateStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, sessionStateStore: sessionStateStore)

        _ = try controller.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchSpace(to: "1")
        try sessionStateStore.flushPendingWrites()
        XCTAssertEqual(try XCTUnwrap(sessionStateStore.load()).hiddenWindows.map(\.windowID), [200])

        windowSystem.focusedWindow = 200
        let result = try controller.handleFocusedWindowChanged().focusedWindowSync
        try sessionStateStore.flushPendingWrites()

        XCTAssertEqual(result, .switched(windowID: 200, space: "2"))
        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertFalse(controller.isHiddenBySpace(200))
        XCTAssertEqual(windowSystem.focusedIDs.last, 200)
        XCTAssertEqual(try XCTUnwrap(sessionStateStore.load()).hiddenWindows.map(\.windowID), [100])
    }

    func testNewWindowDiscoveredOnCurrentSpaceThenHiddenWhenSwitchingAway() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let windowSystem = FakeWindowSystem(windows: windows())
        let sessionStateStore = sessionStateStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, sessionStateStore: sessionStateStore)

        _ = try controller.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchSpace(to: "2")

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

        _ = try controller.switchSpace(to: "1")
        try sessionStateStore.flushPendingWrites()

        XCTAssertTrue(controller.isHiddenBySpace(200))
        XCTAssertTrue(controller.isHiddenBySpace(300))
        XCTAssertEqual(windowSystem.positions[200], hidePoint)
        XCTAssertEqual(windowSystem.positions[300], hidePoint)
        XCTAssertEqual(
            try XCTUnwrap(sessionStateStore.load()).hiddenWindows.map(\.windowID),
            [200, 300]
        )
    }
}

final class SpaceHeadlessRestartIntegrationTests: SpaceHeadlessIntegrationTestCase {
    func testConfiguredSpaceRecordReassignsToItAfterRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let configStore = FileCosmosConfigStore(url: directory.appendingPathComponent("config.yaml"))
        try configStore.save(CosmosConfig(
            spaces: spaceConfigs(["1", "2", "3", "D"]),
            switcher: CosmosConfig.default.switcher
        ))

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSessionStateStore = sessionStateStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, sessionStateStore: firstSessionStateStore)
        let window200Frame = try XCTUnwrap(firstSystem.frames[200])

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "D", controller: firstController, windowSystem: firstSystem)
        try firstSessionStateStore.flushPendingWrites()
        try firstController.restoreHiddenWindowsForShutdown()

        let persistedConfig = try configStore.load()
        XCTAssertEqual(persistedConfig.spaces.map(\.id), ["1", "2", "3", "D"])
        XCTAssertEqual(try XCTUnwrap(firstSessionStateStore.load()).hiddenWindows.map(\.space), ["D"])

        let secondSystem = FakeWindowSystem(windows: windows(window200Frame: window200Frame))
        let secondSessionStateStore = sessionStateStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, sessionStateStore: secondSessionStateStore)

        let startup = try secondController.bootstrapWindowState()
        try secondSessionStateStore.flushPendingWrites()

        XCTAssertEqual(secondController.spaces, ["1", "2", "3", "D"])
        assertReassigned(startup.reassigned, [(200, "D")])
        XCTAssertEqual(secondController.membership(for: 200), "D")
        XCTAssertTrue(secondController.isHiddenBySpace(200))
        XCTAssertEqual(try XCTUnwrap(secondSessionStateStore.load()).hiddenWindows.map(\.space), ["D"])
    }

    func testClosedHiddenWindowPrunesRecordBeforeRestart() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstSystem = FakeWindowSystem(windows: windows())
        let firstSessionStateStore = sessionStateStore(in: directory)
        let firstController = try makeController(firstSystem, in: directory, sessionStateStore: firstSessionStateStore)

        _ = try firstController.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: firstController, windowSystem: firstSystem)
        try firstSessionStateStore.flushPendingWrites()
        XCTAssertEqual(try XCTUnwrap(firstSessionStateStore.load()).hiddenWindows.map(\.windowID), [200])

        firstSystem.windows.removeAll { $0.id == 200 }
        _ = try firstController.handleWindowSetChanged()
        try firstSessionStateStore.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionStateURL(in: directory).path))

        let secondSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes")
        ])
        let secondSessionStateStore = sessionStateStore(in: directory)
        let secondController = try makeController(secondSystem, in: directory, sessionStateStore: secondSessionStateStore)

        let startup = try secondController.bootstrapWindowState()

        XCTAssertTrue(startup.isEmpty)
        XCTAssertEqual(secondController.membership(for: 100), "1")
        XCTAssertTrue(try XCTUnwrap(secondSessionStateStore.load()).hiddenWindows.isEmpty)
    }

    func testEmergencyUnhideRestoresMultipleHiddenSpacesWithFileRecords() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let window300 = WindowSnapshot.window(
            id: 300,
            title: "Three",
            pid: 9,
            appName: "Finder"
        )
        let windowSystem = FakeWindowSystem(windows: windows() + [window300])
        let sessionStateStore = sessionStateStore(in: directory)
        let controller = try makeController(windowSystem, in: directory, sessionStateStore: sessionStateStore)
        let window200Frame = try XCTUnwrap(windowSystem.frames[200])
        let window300Frame = try XCTUnwrap(windowSystem.frames[300])

        _ = try controller.bootstrapWindowState()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(300, to: "3", controller: controller, windowSystem: windowSystem)
        try sessionStateStore.flushPendingWrites()
        XCTAssertEqual(
            try XCTUnwrap(sessionStateStore.load()).hiddenWindows.map(\.windowID),
            [200, 300]
        )

        let result = try controller.restoreAllHiddenWindows()
        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [200, 300], unavailable: [], failed: [])
        )
        XCTAssertFalse(controller.isHiddenBySpace(200))
        XCTAssertFalse(controller.isHiddenBySpace(300))
        XCTAssertEqual(windowSystem.frames[200], window200Frame)
        XCTAssertEqual(windowSystem.frames[300], window300Frame)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionStateURL(in: directory).path))
    }
}
