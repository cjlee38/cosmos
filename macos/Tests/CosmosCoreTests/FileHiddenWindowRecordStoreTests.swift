@testable import CosmosCore
import Foundation
import XCTest

final class FileHiddenWindowRecordStoreTests: XCTestCase {
    func testFlushPersistsUpsertsAndRemovals() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("hidden-window-records.json")
        let store = FileHiddenWindowRecordStore(url: url)
        let record = hiddenRecord()

        store.upsertRecord(record)
        try store.flushPendingWrites()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try store.loadRecords(), [record])

        store.removeRecord(windowID: record.windowID, pid: record.pid)
        try store.flushPendingWrites()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try store.loadRecords().isEmpty)
    }

    func testFlushReportsWriteFailureAndClearsItAfterACompletedWrite() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let blockedDirectory = directory.appendingPathComponent("blocked")
        try Data().write(to: blockedDirectory)
        let store = FileHiddenWindowRecordStore(
            url: blockedDirectory.appendingPathComponent("hidden-window-records.json")
        )
        let record = hiddenRecord()

        store.upsertRecord(record)
        XCTAssertThrowsError(try store.flushPendingWrites())

        try FileManager.default.removeItem(at: blockedDirectory)
        try FileManager.default.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)
        store.upsertRecord(record)
        try store.flushPendingWrites()

        XCTAssertEqual(try store.loadRecords(), [record])
    }

    func testAsyncMutationDoesNotOverwriteACorruptRecordFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("hidden-window-records.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: url)
        let store = FileHiddenWindowRecordStore(url: url)

        store.upsertRecord(hiddenRecord(windowID: 100))

        XCTAssertThrowsError(try store.flushPendingWrites())
        XCTAssertEqual(try Data(contentsOf: url), corruptData)

        try FileManager.default.removeItem(at: url)
        store.upsertRecord(hiddenRecord(windowID: 200))
        try store.flushPendingWrites()

        XCTAssertEqual(try store.loadRecords().map(\.windowID), [100, 200])
    }

    func testDuplicateRecordKeysFailToDecodeInsteadOfCrashing() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("hidden-window-records.json")
        let record = hiddenRecord()
        let encodedRecords = try JSONEncoder().encode([record, record])
        let records = try JSONSerialization.jsonObject(with: encodedRecords)
        let data = try JSONSerialization.data(withJSONObject: ["records": records])
        try data.write(to: url)

        XCTAssertThrowsError(try FileHiddenWindowRecordStore(url: url).loadRecords())
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
