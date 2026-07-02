import CoreGraphics
import Foundation

final class WindowRuntimeStore {
    private let recordStore: (any HiddenWindowRecordStore)?
    private var cachedWindows: [WindowSnapshot] = []
    private var windowsByID: [WindowID: WindowSnapshot] = [:]

    init(recordStore: (any HiddenWindowRecordStore)?) {
        self.recordStore = recordStore
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

    func loadHiddenRecords() throws -> [HiddenWindowRecord] {
        guard let recordStore else {
            return []
        }
        return try recordStore.loadRecords()
    }

    func saveHiddenRecord(
        windowID: WindowID,
        workspace: String,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint
    ) {
        guard let recordStore, let window = snapshot(for: windowID) else {
            return
        }

        recordStore.upsertRecord(
            HiddenWindowRecordPolicy.makeRecord(
                window: window,
                workspace: workspace,
                originalFrame: originalFrame,
                hiddenPosition: hiddenPosition
            )
        )
    }

    func removeHiddenRecord(for windowID: WindowID) {
        recordStore?.removeRecord(windowID: windowID, pid: snapshot(for: windowID)?.app.pid)
    }

    func removeHiddenRecord(windowID: WindowID, pid: pid_t) {
        recordStore?.removeRecord(windowID: windowID, pid: pid)
    }

    func removeAllHiddenRecords(for windowID: WindowID) {
        recordStore?.removeRecord(windowID: windowID, pid: nil)
    }

    func flushHiddenRecordWrites() {
        recordStore?.flushPendingWrites()
    }
}
