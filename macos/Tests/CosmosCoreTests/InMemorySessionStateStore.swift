@testable import CosmosCore
import Foundation

final class InMemorySessionStateStore: SessionStateStore {
    private(set) var state: SessionState
    private(set) var flushCallCount = 0
    var flushError: Error?

    var records: [HiddenWindowRecord] {
        state.hiddenWindows
    }

    init(
        records: [HiddenWindowRecord] = [],
        currentSpace: SpaceID = "1",
        visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID] = [1: "1"]
    ) {
        state = SessionState(
            currentSpace: currentSpace,
            visibleSpaceByMonitorSlot: visibleSpaceByMonitorSlot,
            hiddenWindows: records
        )
    }

    func load() throws -> SessionState? {
        state
    }

    func updateSpaceState(
        currentSpace: SpaceID,
        visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID]
    ) {
        state = SessionState(
            currentSpace: currentSpace,
            visibleSpaceByMonitorSlot: visibleSpaceByMonitorSlot,
            hiddenWindows: records
        )
    }

    func upsertRecord(_ record: HiddenWindowRecord) {
        var records = records
        records.removeAll {
            $0.windowID == record.windowID && $0.pid == record.pid
        }
        records.append(record)
        state = SessionState(
            currentSpace: state.currentSpace,
            visibleSpaceByMonitorSlot: state.visibleSpaceByMonitorSlot,
            hiddenWindows: records
        )
    }

    func removeRecord(windowID: WindowID, pid: pid_t?) {
        var records = records
        records.removeAll { record in
            record.windowID == windowID && (pid == nil || record.pid == pid)
        }
        state = SessionState(
            currentSpace: state.currentSpace,
            visibleSpaceByMonitorSlot: state.visibleSpaceByMonitorSlot,
            hiddenWindows: records
        )
    }

    func flushPendingWrites() throws {
        flushCallCount += 1
        if let flushError {
            throw flushError
        }
    }
}
