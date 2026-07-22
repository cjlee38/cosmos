import Foundation

final class WorkspaceDisplayCoordinator {
    private let windowCache: WindowStateCache
    private let runtimeSynchronizer: WorkspaceRuntimeSynchronizer
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowCache: WindowStateCache,
        runtimeSynchronizer: WorkspaceRuntimeSynchronizer,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowCache = windowCache
        self.runtimeSynchronizer = runtimeSynchronizer
        self.monitorSlotResolver = monitorSlotResolver
    }

    func refreshDisplayTopology() throws {
        try windowCache.updateDisplayTopology(monitorSlotResolver.topology())
    }

    func synchronizeDisplayConfiguration(
        state: inout WorkspaceState
    ) throws -> DisplayConfigurationSyncResult {
        let previousTopology = windowCache.displayTopology
        let previousFrames = frames(for: state)
        let sync = try runtimeSynchronizer.synchronize(
            state: &state,
            reconcileVisibleWindowMonitorMembership: false
        )
        let targetFrames = targetFramesForDisplayChange(
            from: previousTopology,
            previousFrames: previousFrames,
            state: state
        )
        return DisplayConfigurationSyncResult(sync: sync, targetFrames: targetFrames)
    }

    func targetFramesForConfiguredMonitors(state: WorkspaceState) -> [WindowID: WindowFrame] {
        let topology = windowCache.displayTopology
        return state.assignedWindowIDs.reduce(into: [:]) { frames, id in
            guard let workspace = state.membership(for: id),
                  let frame = frame(for: id, state: state)
            else {
                return
            }
            let targetSlot = state.monitorSlot(
                for: workspace,
                availableMonitorSlots: topology.availableMonitorSlots
            )
            guard monitorSlotResolver.slot(containing: frame, among: topology.monitorSlots) != targetSlot,
                  let translatedFrame = monitorSlotResolver.translatedFrame(
                      frame,
                      to: targetSlot,
                      among: topology.monitorSlots
                  )
            else {
                return
            }
            frames[id] = translatedFrame
        }
    }

    private func targetFramesForDisplayChange(
        from previousTopology: DisplayTopologySnapshot,
        previousFrames: [WindowID: WindowFrame],
        state: WorkspaceState
    ) -> [WindowID: WindowFrame] {
        let currentTopology = windowCache.displayTopology
        guard !previousTopology.monitorSlots.isEmpty,
              !currentTopology.monitorSlots.isEmpty
        else {
            return [:]
        }

        return state.assignedWindowIDs.reduce(into: [:]) { frames, id in
            guard let workspace = state.membership(for: id),
                  let frame = previousFrames[id]
            else {
                return
            }

            let sourceSlot = state.monitorSlot(
                for: workspace,
                availableMonitorSlots: previousTopology.availableMonitorSlots
            )
            let targetSlot = state.monitorSlot(
                for: workspace,
                availableMonitorSlots: currentTopology.availableMonitorSlots
            )
            guard let sourceDisplay = monitorSlotResolver.display(
                for: sourceSlot,
                among: previousTopology.monitorSlots
            ),
                let targetDisplay = monitorSlotResolver.display(
                    for: targetSlot,
                    among: currentTopology.monitorSlots
                )
            else {
                return
            }
            guard let translatedFrame = monitorSlotResolver.translatedFrame(
                frame,
                from: sourceDisplay,
                to: targetDisplay
            ) else {
                return
            }
            frames[id] = translatedFrame
        }
    }

    private func frames(for state: WorkspaceState) -> [WindowID: WindowFrame] {
        Dictionary(uniqueKeysWithValues: state.assignedWindowIDs.compactMap { id in
            frame(for: id, state: state).map { (id, $0) }
        })
    }

    private func frame(for id: WindowID, state: WorkspaceState) -> WindowFrame? {
        state.hiddenFrame(for: id) ?? windowCache.snapshot(for: id)?.frame
    }
}

struct DisplayConfigurationSyncResult {
    let sync: WorkspaceSyncSummary
    let targetFrames: [WindowID: WindowFrame]
}
