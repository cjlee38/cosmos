import CoreGraphics
@testable import CosmosCore
import Foundation
import XCTest

private enum HiddenWindowRecordTestError: Error {
    case flushFailed
}

class SpaceHiddenWindowRecordTestCase: SpaceControllerTestCase {
    func hiddenRecord(
        windowID: WindowID = 100,
        originalFrame: WindowFrame,
        space: SpaceID
    ) -> HiddenWindowRecord {
        HiddenWindowRecord(
            windowID: windowID,
            pid: 7,
            space: space,
            originalFrame: originalFrame,
            hiddenPosition: hidePoint
        )
    }
}

final class SpaceHiddenWindowRecordTests: SpaceHiddenWindowRecordTestCase {
    func testHideWritesHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Notes")
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(sessionStateStore.records, [
            HiddenWindowRecord(
                windowID: 100,
                pid: 7,
                space: "2",
                originalFrame: originalFrame,
                hiddenPosition: hidePoint
            )
        ])
    }

    func testNormalRestoreRemovesHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])

        _ = try controller.switchSpace(to: "2")

        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testRefreshFailureDoesNotPruneHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.refreshError = FakeWindowSystemError.refresh

        XCTAssertThrowsError(try controller.handleWindowSetChanged())

        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(controller.isHiddenBySpace(100))
    }

    func testHideSetPositionFailureDoesNotKeepNewHiddenRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        windowSystem.frameWriteFailures.insert(100)

        _ = try controller.handleWindowSetChanged()

        let move = { try self.moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem) }
        XCTAssertThrowsError(try move()) { error in
            XCTAssertEqual(error as? FakeWindowSystemError, .frameWrite(100))
        }
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(controller.isHiddenBySpace(100))
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testRestoreSetPositionFailureKeepsHiddenStateAndRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])

        windowSystem.frameWriteFailures.insert(100)
        XCTAssertThrowsError(try controller.switchSpace(to: "2")) { error in
            guard let transactionError = error as? SpaceTransactionError else {
                return XCTFail("Expected SpaceTransactionError, got \(error)")
            }
            XCTAssertEqual(transactionError.applyError as? FakeWindowSystemError, .frameWrite(100))
            XCTAssertEqual(transactionError.rollbackError as? FakeWindowSystemError, .frameWrite(100))
        }

        XCTAssertTrue(controller.isHiddenBySpace(100))
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])
    }

    func testNormalHideDoesNotSynchronouslyFlushRecords() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(sessionStateStore.flushCallCount, 0)
    }

    func testShutdownRestoresWindowBeforeReportingRecordFlushFailure() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        sessionStateStore.flushError = HiddenWindowRecordTestError.flushFailed

        XCTAssertThrowsError(try controller.restoreHiddenWindowsForShutdown())
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertEqual(sessionStateStore.flushCallCount, 1)
    }

    func testEmergencyRestoreRestoresWindowBeforeReportingRecordFlushFailure() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        sessionStateStore.flushError = HiddenWindowRecordTestError.flushFailed

        XCTAssertThrowsError(try controller.restoreAllHiddenWindows())
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertFalse(controller.isHiddenBySpace(100))
        XCTAssertEqual(sessionStateStore.flushCallCount, 1)
    }

    func testEmergencyUnhideRestoresAllHiddenWindowsAndRemovesRecords() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7),
            .window(id: 300, title: "Three", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        let frame100 = try XCTUnwrap(windowSystem.frames[100])
        let frame200 = try XCTUnwrap(windowSystem.frames[200])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(300, to: "3", controller: controller, windowSystem: windowSystem)

        let result = try controller.restoreAllHiddenWindows()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [200, 300], unavailable: [], failed: [])
        )
        XCTAssertFalse(controller.isHiddenBySpace(200))
        XCTAssertFalse(controller.isHiddenBySpace(300))
        XCTAssertEqual(windowSystem.frames[200], frame200)
        XCTAssertEqual(windowSystem.frames[100], frame100)
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testEmergencyUnhideSkipsClosedHiddenWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.windows.removeAll { $0.id == 200 }

        let result = try controller.restoreAllHiddenWindows()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [], unavailable: [200], failed: [])
        )
        XCTAssertFalse(controller.isHiddenBySpace(200))
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testEmergencyUnhideReportsWindowRestoreFailuresSeparately() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(200)

        let result = try controller.restoreAllHiddenWindows()

        XCTAssertEqual(
            result,
            RestoreAllHiddenWindowsResult(restored: [], unavailable: [], failed: [200])
        )
        XCTAssertTrue(controller.isHiddenBySpace(200))
    }

    func testWindowSyncRemovesRecordForClosedHiddenWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7),
            .window(id: 200, title: "Two", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [200])

        windowSystem.windows.removeAll { $0.id == 200 }
        _ = try controller.handleWindowSetChanged()

        XCTAssertFalse(controller.isHiddenBySpace(200))
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testShutdownRestoreDoesNotRemoveHiddenWindowRecord() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7)
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        XCTAssertEqual(windowSystem.positions[100], hidePoint)

        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])
    }

    func testShutdownRestoreUsesCurrentDisplayWhenHiddenFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 1400, y: 120, width: 300, height: 240))
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        try controller.restoreHiddenWindowsForShutdown()

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])
    }
}

final class HiddenWindowAppliedPositionTests: SpaceHiddenWindowRecordTestCase {
    func testHideRecordsAppliedPositionAfterWindowAdjustsRequestedPosition() throws {
        let originalFrame = WindowFrame.frame(x: 0, y: 31, width: 2560, height: 1409)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, appName: "Zed", frame: originalFrame)
        ])
        windowSystem.appliedPosition = { _, point in
            CGPoint(x: point.x, y: point.y - 27)
        }
        let displayProvider = FakeDisplayProvider(snapshots: [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                visibleFrame: CGRect(x: 0, y: 31, width: 2560, height: 1409),
                role: .main
            )
        ])
        let sessionStateStore = InMemorySessionStateStore()
        let controller = SpaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: WindowParkingPointProvider(displayProvider: displayProvider),
            sessionStateStore: sessionStateStore
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(sessionStateStore.records.map(\.hiddenPosition), [
            CGPoint(x: 2559, y: 1412)
        ])
        XCTAssertEqual(windowSystem.frames[100]?.origin, sessionStateStore.records[0].hiddenPosition)
    }

    func testHideKeepsRequestedPositionWhenImmediateReadbackIsNotParked() throws {
        let originalFrame = WindowFrame.frame(x: 100, y: 100)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: originalFrame)
        ])
        windowSystem.frameReadOverrides[100] = originalFrame
        let sessionStateStore = InMemorySessionStateStore()
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(sessionStateStore.records.map(\.hiddenPosition), [hidePoint])
        XCTAssertEqual(windowSystem.positions[100], hidePoint)
    }
}
