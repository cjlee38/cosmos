import CoreGraphics
@testable import CosmosCore
import XCTest

final class SpaceStartupHiddenWindowRecordTests: SpaceHiddenWindowRecordTestCase {
    func testStartupRecordsRestoreCornerWindowAndReassignSpace() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let record = hiddenRecord(originalFrame: originalFrame, space: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testStartupRecordsRecognizeWindowAdjustedWithinParkingEdge() throws {
        let originalFrame = WindowFrame.frame(x: 0, y: 31, width: 2560, height: 1409)
        let record = HiddenWindowRecord(
            windowID: 100,
            pid: 7,
            space: "2",
            originalFrame: originalFrame,
            hiddenPosition: CGPoint(x: 2559, y: 1439)
        )
        let windowSystem = FakeWindowSystem(windows: [
            .window(
                id: 100,
                title: "Zed",
                pid: 7,
                frame: .frame(x: 2559, y: 1412, width: 2560, height: 1409)
            )
        ])
        let displayProvider = FakeDisplayProvider(snapshots: [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                visibleFrame: CGRect(x: 0, y: 31, width: 2560, height: 1409),
                role: .main
            )
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = SpaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: WindowParkingPointProvider(displayProvider: displayProvider),
            sessionStateStore: sessionStateStore
        )

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "2")])
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testStartupRecordsUseRecordedPositionWhenCurrentParkingCornerChanged() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let record = hiddenRecord(originalFrame: originalFrame, space: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(
                id: 100,
                title: "One",
                pid: 7,
                frame: .frame(x: hidePoint.x, y: hidePoint.y)
            )
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let displayProvider = FakeDisplayProvider(point: CGPoint(x: 999, y: 999))
        let controller = SpaceController(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: displayProvider,
            sessionStateStore: sessionStateStore
        )

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "2")])
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testStartupRecordsRestoreOffscreenOriginalFrameInsideCurrentDisplay() throws {
        let originalFrame = WindowFrame.frame(x: 1400, y: 120, width: 300, height: 240)
        let record = hiddenRecord(originalFrame: originalFrame, space: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(
                id: 100,
                title: "One",
                pid: 7,
                frame: .frame(x: hidePoint.x, y: hidePoint.y, width: 300, height: 240)
            )
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testStartupRecordsReassignOriginalFrameWindowWithoutRestoring() throws {
        let originalFrame = WindowFrame.frame(x: 120, y: 140)
        let record = hiddenRecord(originalFrame: originalFrame, space: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: originalFrame)
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        assertReassigned(result.reassigned, [(100, "2")])
        XCTAssertTrue(result.ignored.isEmpty)
        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertTrue(sessionStateStore.records.isEmpty)
        XCTAssertFalse(windowSystem.operations.contains(.setPosition(100, originalFrame.origin)))
    }

    func testStartupRecordsIgnorePidMismatch() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), space: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 8, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.reassigned.isEmpty)
        XCTAssertEqual(result.ignored, [record])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(sessionStateStore.records, [record])
    }

    func testStartupRecordsIgnoreWindowMovedAwayFromHiddenAndOriginalPosition() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), space: "2")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: 900, y: 900))
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertTrue(result.reassigned.isEmpty)
        XCTAssertEqual(result.ignored, [record])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(sessionStateStore.records, [record])
    }

    func testStartupRecordsRestoreMissingSpaceWindowIntoCurrentSpace() throws {
        let record = hiddenRecord(originalFrame: .frame(x: 120, y: 140), space: "A")
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        let sessionStateStore = InMemorySessionStateStore(records: [record])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.restored, [100])
        assertReassigned(result.reassigned, [(100, "1")])
        XCTAssertEqual(controller.spaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(windowSystem.frames[100], record.originalFrame)
        XCTAssertTrue(sessionStateStore.records.isEmpty)
    }

    func testStartupRestoreFailureDoesNotBlockLaterRecords() throws {
        let first = hiddenRecord(
            windowID: 100,
            originalFrame: .frame(x: 120, y: 140),
            space: "2"
        )
        let second = hiddenRecord(
            windowID: 200,
            originalFrame: .frame(x: 220, y: 240),
            space: "2"
        )
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y)),
            .window(id: 200, title: "Two", pid: 7, frame: .frame(x: hidePoint.x, y: hidePoint.y))
        ])
        windowSystem.frameWriteFailures.insert(100)
        let sessionStateStore = InMemorySessionStateStore(records: [first, second])
        let controller = makeController(windowSystem, sessionStateStore: sessionStateStore)

        let result = try controller.applyHiddenWindowRecordsAtStartup()

        XCTAssertEqual(result.failed, [100])
        XCTAssertEqual(result.restored, [200])
        assertReassigned(result.reassigned, [(200, "2")])
        XCTAssertEqual(sessionStateStore.records.map(\.windowID), [100])
        XCTAssertEqual(controller.membership(for: 200), "2")
    }
}
