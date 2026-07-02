import Foundation

final class WindowSetSynchronizer {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore

    init(windowSystem: any WindowSystem, windowStore: WindowRuntimeStore) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
    }

    func refresh(state: inout WorkspaceState) -> WindowListResult {
        let windows = windowSystem.refresh()
        windowStore.replaceWindows(windows)

        let aliveIDs = Set(windows.map(\.id))
        let sync = state.sync(aliveWindowIDs: aliveIDs)
        for id in sync.removed {
            windowStore.removeAllHiddenRecords(for: id)
        }

        return WindowListResult(windows: windows, sync: sync)
    }
}
