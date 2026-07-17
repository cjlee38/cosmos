import Foundation

final class WorkspaceDisplayCoordinator {
    private let windowStore: WindowRuntimeStore
    private let windowSetSynchronizer: WindowSetSynchronizer
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowStore: WindowRuntimeStore,
        windowSetSynchronizer: WindowSetSynchronizer,
        visibilityCoordinator: WorkspaceVisibilityCoordinator,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowStore = windowStore
        self.windowSetSynchronizer = windowSetSynchronizer
        self.visibilityCoordinator = visibilityCoordinator
        self.monitorSlotResolver = monitorSlotResolver
    }

    func handleDisplayConfigurationChanged(
        state: inout WorkspaceState
    ) throws -> ExternalWindowEventResult {
        let previousTopology = windowStore.displayTopology
        let previousFrames = frames(for: state)
        let sync = windowSetSynchronizer.refresh(
            state: &state,
            reconcileVisibleWindowMonitorMembership: false
        ).sync
        let targetFrames = targetFramesForDisplayChange(
            from: previousTopology,
            previousFrames: previousFrames,
            state: state
        )
        try visibilityCoordinator.applyVisibleWorkspaces(
            state: &state,
            targetFrames: targetFrames
        )
        return ExternalWindowEventResult(sync: sync, focusedWindowSync: nil)
    }

    func targetFramesForConfiguredMonitors(state: WorkspaceState) -> [WindowID: WindowFrame] {
        let topology = windowStore.displayTopology
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
        let currentTopology = windowStore.displayTopology
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
                ),
                let translatedFrame = monitorSlotResolver.translatedFrame(
                    frame,
                    from: sourceDisplay,
                    to: targetDisplay
                )
            else {
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
        state.hiddenFrame(for: id) ?? windowStore.snapshot(for: id)?.frame
    }
}

public extension WorkspaceController {
    @discardableResult
    func updateWorkspaceMonitor(_ workspace: String, displayID: DisplayID) throws -> WorkspaceSyncSummary {
        let monitorSlot = try WorkspaceDisplayAssignment.monitorSlot(
            for: displayID,
            monitorSlots: monitorSlots
        )
        return try updateConfig(currentConfig.assigningWorkspace(workspace, toMonitorSlot: monitorSlot))
    }
}
