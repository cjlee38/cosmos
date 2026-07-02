import Foundation

public final class FileHiddenWindowRecordStore: HiddenWindowRecordStore {
    public static let `default`: FileHiddenWindowRecordStore = {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kkaci", isDirectory: true)
        return FileHiddenWindowRecordStore(
            url: directory.appendingPathComponent("hidden-window-records.json"),
            legacyURL: directory.appendingPathComponent("snapshot.json")
        )
    }()

    public let url: URL
    private let legacyURL: URL?
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "kkaci.hidden-window-record-store")
    private var recordsByKey: [RecordKey: HiddenWindowRecord]?

    public init(url: URL, legacyURL: URL? = nil, fileManager: FileManager = .default) {
        self.url = url
        self.legacyURL = legacyURL
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
                for key in recordsByKey?.keys.filter({ $0.windowID == windowID }) ?? [] {
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

        guard let sourceURL = readableURL() else {
            recordsByKey = [:]
            return
        }

        let data = try Data(contentsOf: sourceURL)
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

    private func readableURL() -> URL? {
        if fileManager.fileExists(atPath: url.path) {
            return url
        }
        if let legacyURL, fileManager.fileExists(atPath: legacyURL.path) {
            return legacyURL
        }
        return nil
    }

    private func removePersistedRecordFiles() throws {
        for fileURL in [url, legacyURL].compactMap({ $0 }) {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
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

    init(records: [HiddenWindowRecord]) {
        self.records = records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let records = try container.decodeIfPresent([HiddenWindowRecord].self, forKey: .records) {
            self.records = records
        } else {
            self.records = try container.decode([HiddenWindowRecord].self, forKey: .legacySnapshots)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
    }

    private enum CodingKeys: String, CodingKey {
        case records
        case legacySnapshots = "snapshots"
    }
}

private struct RecordKey: Hashable {
    let windowID: WindowID
    let pid: pid_t

    init(windowID: WindowID, pid: pid_t) {
        self.windowID = windowID
        self.pid = pid
    }

    init(_ record: HiddenWindowRecord) {
        self.windowID = record.windowID
        self.pid = record.pid
    }
}
