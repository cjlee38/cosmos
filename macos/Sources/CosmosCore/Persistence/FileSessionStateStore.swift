import Foundation

public final class FileSessionStateStore: SessionStateStore {
    public static let `default`: FileSessionStateStore = {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cosmos", isDirectory: true)
        return FileSessionStateStore(url: directory.appendingPathComponent("session-state.json"))
    }()

    public let url: URL
    private let fileManager: FileManager
    private let legacyURL: URL
    private let queue = DispatchQueue(label: "cosmos.session-state-store")
    private var cachedState: SessionState?
    private var didLoadState = false
    private var pendingMutations: [SessionMutation] = []
    private var pendingWriteError: Error?

    public init(
        url: URL,
        legacyURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.legacyURL = legacyURL
            ?? url.deletingLastPathComponent().appendingPathComponent("hidden-window-records.json")
        self.fileManager = fileManager
    }

    public func load() throws -> SessionState? {
        try queue.sync {
            if let pendingWriteError {
                throw pendingWriteError
            }
            return try sessionState()
        }
    }

    public func updateSpaceState(
        currentSpace: SpaceID,
        visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID]
    ) {
        enqueue(.updateSpaces(
            currentSpace: currentSpace,
            visibleSpaceByMonitorSlot: visibleSpaceByMonitorSlot
        ))
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

    private func sessionState() throws -> SessionState? {
        if didLoadState {
            return cachedState
        }

        guard fileManager.fileExists(atPath: url.path) else {
            if fileManager.fileExists(atPath: legacyURL.path) {
                let data = try Data(contentsOf: legacyURL)
                let legacyState = try JSONDecoder().decode(LegacySessionState.self, from: data)
                try validateUniqueHiddenWindows(legacyState.records)
                let state = SessionState(hiddenWindows: legacyState.records)
                cachedState = state
                didLoadState = true
                return state
            }
            didLoadState = true
            return nil
        }

        let data = try Data(contentsOf: url)
        let state = try JSONDecoder().decode(SessionState.self, from: data)
        try validateUniqueHiddenWindows(state.hiddenWindows)
        cachedState = state
        didLoadState = true
        return state
    }

    private func enqueue(_ mutation: SessionMutation) {
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

        let initialState = try sessionState()
        var state = pendingMutations[0].applying(to: initialState)
        for mutation in pendingMutations.dropFirst() {
            state = mutation.applying(to: state)
        }
        try write(state)
        cachedState = state
        pendingMutations.removeAll()
        pendingWriteError = nil
    }

    private func write(_ state: SessionState) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
        if fileManager.fileExists(atPath: legacyURL.path) {
            try fileManager.removeItem(at: legacyURL)
        }
    }

    private func validateUniqueHiddenWindows(_ records: [HiddenWindowRecord]) throws {
        var keys: Set<RecordKey> = []
        for record in records {
            guard keys.insert(RecordKey(record)).inserted else {
                throw DecodingError.dataCorrupted(
                    DecodingError.Context(
                        codingPath: [],
                        debugDescription: "Duplicate hidden window for \(record.windowID), pid \(record.pid)"
                    )
                )
            }
        }
    }
}

private enum SessionMutation {
    case updateSpaces(
        currentSpace: SpaceID,
        visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID]
    )
    case upsert(HiddenWindowRecord)
    case remove(windowID: WindowID, pid: pid_t?)

    func applying(to state: SessionState?) -> SessionState {
        switch self {
        case let .updateSpaces(currentSpace, visibleSpaceByMonitorSlot):
            return SessionState(
                currentSpace: currentSpace,
                visibleSpaceByMonitorSlot: visibleSpaceByMonitorSlot,
                hiddenWindows: state?.hiddenWindows ?? []
            )
        case let .upsert(record):
            let currentState = state ?? SessionState()
            var records = recordsByKey(currentState.hiddenWindows)
            records[RecordKey(record)] = record
            return currentState.with(hiddenWindows: sortedRecords(records))
        case let .remove(windowID, pid):
            let currentState = state ?? SessionState()
            var records = recordsByKey(currentState.hiddenWindows)
            if let pid {
                records[RecordKey(windowID: windowID, pid: pid)] = nil
            } else {
                for key in records.keys.filter({ $0.matches(windowID: windowID) }) {
                    records[key] = nil
                }
            }
            return currentState.with(hiddenWindows: sortedRecords(records))
        }
    }

    private func recordsByKey(
        _ records: [HiddenWindowRecord]
    ) -> [RecordKey: HiddenWindowRecord] {
        Dictionary(uniqueKeysWithValues: records.map { (RecordKey($0), $0) })
    }

    private func sortedRecords(
        _ records: [RecordKey: HiddenWindowRecord]
    ) -> [HiddenWindowRecord] {
        records.values.sorted {
            if $0.pid == $1.pid {
                return $0.windowID < $1.windowID
            }
            return $0.pid < $1.pid
        }
    }
}

private struct LegacySessionState: Codable {
    let records: [HiddenWindowRecord]
}

private extension SessionState {
    func with(hiddenWindows: [HiddenWindowRecord]) -> SessionState {
        SessionState(
            currentSpace: currentSpace,
            visibleSpaceByMonitorSlot: visibleSpaceByMonitorSlot,
            hiddenWindows: hiddenWindows
        )
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
        self.init(windowID: record.windowID, pid: record.pid)
    }

    func matches(windowID: WindowID) -> Bool {
        self.windowID == windowID
    }
}
