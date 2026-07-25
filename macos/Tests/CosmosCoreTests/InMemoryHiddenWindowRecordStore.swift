import Foundation
@testable import CosmosCore

final class InMemoryHiddenWindowRecordStore: HiddenWindowRecordStore {
    private(set) var records: [HiddenWindowRecord]
    private(set) var flushCallCount = 0
    var flushError: Error?

    init(records: [HiddenWindowRecord] = []) {
        self.records = records
    }

    func loadRecords() throws -> [HiddenWindowRecord] {
        records
    }

    func upsertRecord(_ record: HiddenWindowRecord) {
        records.removeAll {
            $0.windowID == record.windowID && $0.pid == record.pid
        }
        records.append(record)
    }

    func removeRecord(windowID: WindowID, pid: pid_t?) {
        records.removeAll { record in
            record.windowID == windowID && (pid == nil || record.pid == pid)
        }
    }

    func flushPendingWrites() throws {
        flushCallCount += 1
        if let flushError {
            throw flushError
        }
    }
}
