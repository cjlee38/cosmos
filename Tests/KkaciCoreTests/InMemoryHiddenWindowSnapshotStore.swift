import Foundation
@testable import KkaciCore

final class InMemoryHiddenWindowSnapshotStore: HiddenWindowSnapshotStoring {
    private(set) var snapshots: [HiddenWindowSnapshot]

    init(snapshots: [HiddenWindowSnapshot] = []) {
        self.snapshots = snapshots
    }

    func loadSnapshots() throws -> [HiddenWindowSnapshot] {
        snapshots
    }

    func upsertSnapshot(_ snapshot: HiddenWindowSnapshot) {
        snapshots.removeAll {
            $0.windowID == snapshot.windowID && $0.pid == snapshot.pid
        }
        snapshots.append(snapshot)
    }

    func removeSnapshot(windowID: WindowID, pid: pid_t?) {
        snapshots.removeAll { snapshot in
            snapshot.windowID == windowID && (pid == nil || snapshot.pid == pid)
        }
    }

    func flushPendingWrites() {}
}
