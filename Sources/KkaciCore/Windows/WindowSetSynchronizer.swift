import Foundation

final class WindowSetSynchronizer {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let recordRepository: HiddenWindowRecordRepository
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowSystem: any WindowSystem,
        windowStore: WindowRuntimeStore,
        recordRepository: HiddenWindowRecordRepository,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
        self.recordRepository = recordRepository
        self.monitorSlotResolver = monitorSlotResolver
    }

    func refresh(
        state: inout WorkspaceState,
        reconcileVisibleWindowMonitorMembership: Bool = true
    ) -> WindowDiscoveryResult {
        let windows = windowSystem.refresh()
        let displayTopology = monitorSlotResolver.topology()
        windowStore.replace(
            windows: windows,
            focusedWindowID: windowSystem.focusedWindowID(),
            displayTopology: displayTopology
        )

        let sync = state.sync(
            windows: windows,
            availableMonitorSlots: displayTopology.availableMonitorSlots,
            reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership
        ) { frame in
            monitorSlotResolver.slot(containing: frame, among: displayTopology.monitorSlots)
        }
        for id in sync.removed {
            recordRepository.removeAllRecords(for: id)
        }

        return WindowDiscoveryResult(windows: windows, sync: sync)
    }
}
