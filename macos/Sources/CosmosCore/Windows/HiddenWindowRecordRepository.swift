import Foundation

final class HiddenWindowRecordRepository {
    private let store: (any SessionStateStore)?

    init(store: (any SessionStateStore)?) {
        self.store = store
    }

    func loadRecords() throws -> [HiddenWindowRecord] {
        try store?.load()?.hiddenWindows ?? []
    }

    func record(windowID: WindowID, pid: pid_t) throws -> HiddenWindowRecord? {
        try loadRecords().first {
            $0.windowID == windowID && $0.pid == pid
        }
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
