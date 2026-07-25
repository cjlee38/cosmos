import Foundation

final class HiddenWindowRecordRepository {
    private let store: (any HiddenWindowRecordStore)?

    init(store: (any HiddenWindowRecordStore)?) {
        self.store = store
    }

    func loadRecords() throws -> [HiddenWindowRecord] {
        try store?.loadRecords() ?? []
    }

    func upsertRecord(_ record: HiddenWindowRecord) {
        store?.upsertRecord(record)
    }

    func removeRecord(windowID: WindowID, pid: pid_t?) {
        store?.removeRecord(windowID: windowID, pid: pid)
    }

    func removeAllRecords(for windowID: WindowID) {
        store?.removeRecord(windowID: windowID, pid: nil)
    }

    func flushPendingWrites() throws {
        try store?.flushPendingWrites()
    }
}
