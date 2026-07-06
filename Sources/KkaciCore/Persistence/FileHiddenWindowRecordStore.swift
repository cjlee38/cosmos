import Foundation

public final class FileHiddenWindowRecordStore: HiddenWindowRecordStore {
    public static let `default`: FileHiddenWindowRecordStore = {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kkaci", isDirectory: true)
        return FileHiddenWindowRecordStore(url: directory.appendingPathComponent("hidden-window-records.json"))
    }()

    public let url: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "kkaci.hidden-window-record-store")
    private var recordsByKey: [RecordKey: HiddenWindowRecord]?

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func loadRecords() throws -> [HiddenWindowRecord] {
        try queue.sync {
            try loadRecordsIfNeeded()
            return sortedRecords()
        }
    }

    public func upsertRecord(_ record: HiddenWindowRecord) {
        queue.async { [self] in
            loadRecordsForAsyncMutation()
            recordsByKey?[RecordKey(record)] = record
            writeRecordsIgnoringErrors()
        }
    }

    public func removeRecord(windowID: WindowID, pid: pid_t?) {
        queue.async { [self] in
            loadRecordsForAsyncMutation()
            guard recordsByKey != nil else {
                return
            }

            if let pid {
                recordsByKey?[RecordKey(windowID: windowID, pid: pid)] = nil
            } else {
                for key in recordsByKey?.keys.filter({ $0.matches(windowID: windowID) }) ?? [] {
                    recordsByKey?[key] = nil
                }
            }
            writeRecordsIgnoringErrors()
        }
    }

    public func flushPendingWrites() {
        queue.sync {}
    }

    private func loadRecordsIfNeeded() throws {
        guard recordsByKey == nil else {
            return
        }

        guard fileManager.fileExists(atPath: url.path) else {
            recordsByKey = [:]
            return
        }

        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(RecordDocument.self, from: data)
        recordsByKey = Dictionary(uniqueKeysWithValues: document.records.map {
            (RecordKey($0), $0)
        })
    }

    private func loadRecordsForAsyncMutation() {
        if recordsByKey == nil {
            try? loadRecordsIfNeeded()
        }
        if recordsByKey == nil {
            recordsByKey = [:]
        }
    }

    private func writeRecordsIgnoringErrors() {
        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let records = sortedRecords()
            guard !records.isEmpty else {
                try removePersistedRecordFiles()
                return
            }

            let data = try JSONEncoder().encode(RecordDocument(records: records))
            try data.write(to: url, options: .atomic)
        } catch {
            // Record persistence must not block or fail window manipulation.
        }
    }

    private func removePersistedRecordFiles() throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func sortedRecords() -> [HiddenWindowRecord] {
        (recordsByKey ?? [:])
            .values
            .sorted {
                if $0.pid == $1.pid {
                    return $0.windowID < $1.windowID
                }
                return $0.pid < $1.pid
            }
    }
}

private struct RecordDocument: Codable {
    let records: [HiddenWindowRecord]

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
    }

    private enum CodingKeys: String, CodingKey {
        case records
    }
}

private struct RecordKey: Hashable {
    private let windowID: WindowID
    private let pid: pid_t

    init(windowID: WindowID, pid: pid_t) {
        self.windowID = windowID
        self.pid = pid
    }

    init(_ record: HiddenWindowRecord) {
        windowID = record.windowID
        pid = record.pid
    }

    func matches(windowID: WindowID) -> Bool {
        self.windowID == windowID
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(pid)
    }
}
