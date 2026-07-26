@testable import CosmosCore
import Foundation
import XCTest

final class FileSessionStateStoreTests: XCTestCase {
    func testLegacyRecordsAreImportedAndRemovedAfterUnifiedStateIsWritten() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("session-state.json")
        let legacyURL = directory.appendingPathComponent("hidden-window-records.json")
        let record = hiddenRecord()
        let encodedRecords = try JSONEncoder().encode([record])
        let records = try JSONSerialization.jsonObject(with: encodedRecords)
        let legacyData = try JSONSerialization.data(withJSONObject: ["records": records])
        try legacyData.write(to: legacyURL)
        let store = FileSessionStateStore(url: url, legacyURL: legacyURL)

        XCTAssertEqual(try store.load()?.hiddenWindows, [record])

        store.updateSpaceState(currentSpace: "2", visibleSpaceByMonitorSlot: [1: "2"])
        try store.flushPendingWrites()

        XCTAssertEqual(
            try store.load(),
            SessionState(
                currentSpace: "2",
                visibleSpaceByMonitorSlot: [1: "2"],
                hiddenWindows: [record]
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testHiddenWindowMutationBeforeSpaceInitializationDoesNotPoisonTheStore() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileSessionStateStore(
            url: directory.appendingPathComponent("session-state.json")
        )
        let record = hiddenRecord()

        store.upsertRecord(record)
        store.updateSpaceState(currentSpace: "1", visibleSpaceByMonitorSlot: [1: "1"])
        try store.flushPendingWrites()

        XCTAssertEqual(
            try store.load(),
            SessionState(
                currentSpace: "1",
                visibleSpaceByMonitorSlot: [1: "1"],
                hiddenWindows: [record]
            )
        )
    }

    func testSpaceStateUpdatePreservesHiddenWindowsInTheSameDocument() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileSessionStateStore(
            url: directory.appendingPathComponent("session-state.json")
        )
        let record = hiddenRecord()

        store.updateSpaceState(currentSpace: "1", visibleSpaceByMonitorSlot: [1: "1"])
        store.upsertRecord(record)
        store.updateSpaceState(currentSpace: "2", visibleSpaceByMonitorSlot: [1: "2"])
        try store.flushPendingWrites()

        XCTAssertEqual(
            try store.load(),
            SessionState(
                currentSpace: "2",
                visibleSpaceByMonitorSlot: [1: "2"],
                hiddenWindows: [record]
            )
        )
    }

    func testFlushPersistsUpsertsAndRemovals() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("session-state.json")
        let store = FileSessionStateStore(url: url)
        let record = hiddenRecord()

        store.updateSpaceState(currentSpace: "1", visibleSpaceByMonitorSlot: [1: "1"])
        store.upsertRecord(record)
        try store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.load()?.hiddenWindows, [record])

        store.removeRecord(windowID: record.windowID, pid: record.pid)
        try store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try XCTUnwrap(store.load()).hiddenWindows.isEmpty)
    }

    func testFlushReportsWriteFailureAndClearsItAfterACompletedWrite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let blockedDirectory = directory.appendingPathComponent("blocked")
        try Data().write(to: blockedDirectory)
        let store = FileSessionStateStore(
            url: blockedDirectory.appendingPathComponent("session-state.json")
        )
        let record = hiddenRecord()

        store.updateSpaceState(currentSpace: "1", visibleSpaceByMonitorSlot: [1: "1"])
        store.upsertRecord(record)
        XCTAssertThrowsError(try store.flushPendingWrites())

        try FileManager.default.removeItem(at: blockedDirectory)
        try FileManager.default.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
        store.upsertRecord(record)
        try store.flushPendingWrites()

        XCTAssertEqual(try store.load()?.hiddenWindows, [record])
    }

    func testAsyncMutationDoesNotOverwriteACorruptRecordFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("session-state.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: url)
        let store = FileSessionStateStore(url: url)

        store.updateSpaceState(currentSpace: "1", visibleSpaceByMonitorSlot: [1: "1"])
        store.upsertRecord(hiddenRecord(windowID: 100))

        XCTAssertThrowsError(try store.flushPendingWrites())
        XCTAssertEqual(try Data(contentsOf: url), corruptData)

        try FileManager.default.removeItem(at: url)
        store.upsertRecord(hiddenRecord(windowID: 200))
        try store.flushPendingWrites()

        XCTAssertEqual(try store.load()?.hiddenWindows.map(\.windowID), [100, 200])
    }

    func testDuplicateRecordKeysFailToDecodeInsteadOfCrashing() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("session-state.json")
        let record = hiddenRecord()
        let data = try JSONEncoder().encode(SessionState(
            currentSpace: "1",
            visibleSpaceByMonitorSlot: [1: "1"],
            hiddenWindows: [record, record]
        ))
        try data.write(to: url)

        XCTAssertThrowsError(try FileSessionStateStore(url: url).load())
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-record-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func hiddenRecord(windowID: WindowID = 100) -> HiddenWindowRecord {
        HiddenWindowRecord(
            windowID: windowID,
            pid: 7,
            space: "2",
            originalFrame: .frame(x: 120, y: 140),
            hiddenPosition: CGPoint(x: -1, y: -1)
        )
    }
}
