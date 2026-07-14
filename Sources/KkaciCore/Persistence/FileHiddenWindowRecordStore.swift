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
    private var pendingMutations: [RecordMutation] = []
    private var pendingWriteError: Error?

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func loadRecords() throws -> [HiddenWindowRecord] {
        try queue.sync {
            if let pendingWriteError {
                throw pendingWriteError
            }
            return try sortedRecords(records())
        }
    }

    public func upsertRecord(_ record: HiddenWindowRecord) {
        enqueue(.upsert(record))
    }

    public func removeRecord(windowID: WindowID, pid: pid_t?) {
        enqueue(.remove(windowID: windowID, pid: pid))
    }

    public func flushPendingWrites() throws {
        try queue.sync {
            do {
                try persistPendingMutations()
            } catch {
                pendingWriteError = error
                throw error
            }
        }
    }

    private func records() throws -> [RecordKey: HiddenWindowRecord] {
        if let recordsByKey {
            return recordsByKey
        }

        guard fileManager.fileExists(atPath: url.path) else {
            recordsByKey = [:]
            return [:]
        }

        let data = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(RecordDocument.self, from: data)
        var records: [RecordKey: HiddenWindowRecord] = [:]
        for record in document.records {
            let key = RecordKey(record)
            guard records[key] == nil else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Duplicate hidden-window record for \(record.windowID), pid \(record.pid)"
                    )
                )
            }
            records[key] = record
        }
        recordsByKey = records
        return records
    }

    private func enqueue(_ mutation: RecordMutation) {
        queue.async { [self] in
            pendingMutations.append(mutation)
            do {
                try persistPendingMutations()
            } catch {
                pendingWriteError = error
            }
        }
    }

    private func persistPendingMutations() throws {
        guard !pendingMutations.isEmpty else {
            if let pendingWriteError {
                throw pendingWriteError
            }
            return
        }

        var records = try records()
        for mutation in pendingMutations {
            mutation.apply(to: &records)
        }
        recordsByKey = records
        try writeRecords(records)
        pendingMutations.removeAll()
        pendingWriteError = nil
    }

    private func writeRecords(_ recordsByKey: [RecordKey: HiddenWindowRecord]) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let records = sortedRecords(recordsByKey)
        guard !records.isEmpty else {
            try removePersistedRecordFiles()
            return
        }

        let data = try JSONEncoder().encode(RecordDocument(records: records))
        try data.write(to: url, options: .atomic)
    }

    private func removePersistedRecordFiles() throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func sortedRecords(
        _ recordsByKey: [RecordKey: HiddenWindowRecord]
    ) -> [HiddenWindowRecord] {
        recordsByKey
            .values
            .sorted {
                if $0.pid == $1.pid {
                    return $0.windowID < $1.windowID
                }
                return $0.pid < $1.pid
            }
    }
}

private enum RecordMutation {
    case upsert(HiddenWindowRecord)
    case remove(windowID: WindowID, pid: pid_t?)

    func apply(to records: inout [RecordKey: HiddenWindowRecord]) {
        switch self {
        case let .upsert(record):
            records[RecordKey(record)] = record
        case let .remove(windowID, pid):
            if let pid {
                records[RecordKey(windowID: windowID, pid: pid)] = nil
            } else {
                for key in records.keys.filter({ $0.matches(windowID: windowID) }) {
                    records[key] = nil
                }
            }
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
