import Foundation

final class WindowSetSynchronizer {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowSystem: any WindowSystem,
        windowStore: WindowRuntimeStore,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
        self.monitorSlotResolver = monitorSlotResolver
    }

    func refresh(state: inout WorkspaceState) -> WindowListResult {
        let windows = windowSystem.refresh()
        windowStore.replaceWindows(windows)

        let sync = state.sync(windows: windows) { frame in
            monitorSlotResolver.slot(containing: frame)
        }
        for id in sync.removed {
            windowStore.removeAllHiddenRecords(for: id)
        }

        return WindowListResult(windows: windows, sync: sync)
    }
}
