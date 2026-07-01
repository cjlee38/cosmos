import CoreGraphics
import Foundation

final class WindowRuntimeStore {
    private let snapshotStore: (any HiddenWindowSnapshotStoring)?
    private var cachedWindows: [WindowSnapshot] = []
    private var windowsByID: [WindowID: WindowSnapshot] = [:]

    init(snapshotStore: (any HiddenWindowSnapshotStoring)?) {
        self.snapshotStore = snapshotStore
    }

    var windows: [WindowSnapshot] {
        cachedWindows
    }

    var windowSnapshotByID: [WindowID: WindowSnapshot] {
        windowsByID
    }

    func replaceWindows(_ windows: [WindowSnapshot]) {
        cachedWindows = windows
        windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
    }

    func snapshot(for id: WindowID) -> WindowSnapshot? {
        windowsByID[id]
    }

    func loadHiddenSnapshots() throws -> [HiddenWindowSnapshot] {
        guard let snapshotStore else {
            return []
        }
        return try snapshotStore.loadSnapshots()
    }

    func saveHiddenSnapshot(
        windowID: WindowID,
        workspace: String,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint
    ) {
        guard let snapshotStore, let window = snapshot(for: windowID) else {
            return
        }

        snapshotStore.upsertSnapshot(
            HiddenWindowSnapshotPolicy.makeSnapshot(
                window: window,
                workspace: workspace,
                originalFrame: originalFrame,
                hiddenPosition: hiddenPosition
            )
        )
    }

    func removeHiddenSnapshot(for windowID: WindowID) {
        snapshotStore?.removeSnapshot(windowID: windowID, pid: snapshot(for: windowID)?.app.pid)
    }

    func removeHiddenSnapshot(windowID: WindowID, pid: pid_t) {
        snapshotStore?.removeSnapshot(windowID: windowID, pid: pid)
    }

    func removeAllHiddenSnapshots(for windowID: WindowID) {
        snapshotStore?.removeSnapshot(windowID: windowID, pid: nil)
    }

    func flushHiddenSnapshotWrites() {
        snapshotStore?.flushPendingWrites()
    }
}
