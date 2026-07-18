import Foundation

final class WorkspaceRuntimeSynchronizer {
    private let windowSystem: any WindowSystem
    private let windowCache: WindowStateCache
    private let recordRepository: HiddenWindowRecordRepository
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowSystem: any WindowSystem,
        windowCache: WindowStateCache,
        recordRepository: HiddenWindowRecordRepository,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowSystem = windowSystem
        self.windowCache = windowCache
        self.recordRepository = recordRepository
        self.monitorSlotResolver = monitorSlotResolver
    }

    func synchronize(
        state: inout WorkspaceState,
        reconcileVisibleWindowMonitorMembership: Bool = true
    ) throws -> WorkspaceSyncSummary {
        let windows = try windowSystem.refresh()
        let displayTopology = try monitorSlotResolver.topology()
        let windowSetDiff = windowCache.replace(
            windows: windows,
            focusedWindowID: windowSystem.focusedWindowID(),
            displayTopology: displayTopology
        )

        let sync = synchronizeMemberships(
            windows: windows,
            windowSetDiff: windowSetDiff,
            displayTopology: displayTopology,
            reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership,
            state: &state
        )
        for id in sync.removed {
            recordRepository.removeAllRecords(for: id)
        }

        return sync
    }

    private func synchronizeMemberships(
        windows: [WindowSnapshot],
        windowSetDiff: WindowSetDiff,
        displayTopology: DisplayTopologySnapshot,
        reconcileVisibleWindowMonitorMembership: Bool,
        state: inout WorkspaceState
    ) -> WorkspaceSyncSummary {
        let liveWindowIDs = Set(windows.map(\.id))
        let relevantWindowIDs = liveWindowIDs.union(windowSetDiff.removed)
        let previousMemberships = Dictionary(uniqueKeysWithValues: relevantWindowIDs.compactMap { id in
            state.membership(for: id).map { (id, $0) }
        })

        for window in windows where !window.isMinimized && state.membership(for: window.id) == nil {
            let monitorSlot = monitorSlotResolver.slot(
                containing: window.frame,
                among: displayTopology.monitorSlots
            )
            state.assign(
                window.id,
                to: state.visibleWorkspace(
                    on: monitorSlot,
                    availableMonitorSlots: displayTopology.availableMonitorSlots
                )
            )
        }

        if reconcileVisibleWindowMonitorMembership {
            reconcileVisibleWindowMemberships(
                windows,
                displayTopology: displayTopology,
                state: &state
            )
        }

        for id in windowSetDiff.removed {
            state.removeWindow(id)
        }

        let changes = relevantWindowIDs.sorted().compactMap { id -> WorkspaceMembershipChange? in
            let previousWorkspace = previousMemberships[id]
            let workspace = state.membership(for: id)
            guard previousWorkspace != workspace else {
                return nil
            }
            return WorkspaceMembershipChange(
                windowID: id,
                previousWorkspace: previousWorkspace?.rawValue,
                workspace: workspace?.rawValue
            )
        }
        return WorkspaceSyncSummary(membershipChanges: changes)
    }

    private func reconcileVisibleWindowMemberships(
        _ windows: [WindowSnapshot],
        displayTopology: DisplayTopologySnapshot,
        state: inout WorkspaceState
    ) {
        for window in windows where !window.isMinimized && !state.isHidden(window.id) {
            guard let workspace = state.membership(for: window.id),
                  let frame = window.frame
            else {
                continue
            }

            let currentSlot = monitorSlotResolver.slot(
                containing: frame,
                among: displayTopology.monitorSlots
            )
            if state.monitorSlot(
                for: workspace,
                availableMonitorSlots: displayTopology.availableMonitorSlots
            ) != currentSlot {
                state.assign(
                    window.id,
                    to: state.visibleWorkspace(
                        on: currentSlot,
                        availableMonitorSlots: displayTopology.availableMonitorSlots
                    )
                )
            }
        }
    }
}
