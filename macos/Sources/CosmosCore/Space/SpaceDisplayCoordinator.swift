import Foundation

final class SpaceDisplayCoordinator {
    private let windowCache: WindowStateCache
    private let runtimeSynchronizer: SpaceRuntimeSynchronizer
    private let monitorSlotResolver: MonitorSlotResolver
    private let hidePointProvider: any HidePointProviding

    init(
        windowCache: WindowStateCache,
        runtimeSynchronizer: SpaceRuntimeSynchronizer,
        monitorSlotResolver: MonitorSlotResolver,
        hidePointProvider: any HidePointProviding
    ) {
        self.windowCache = windowCache
        self.runtimeSynchronizer = runtimeSynchronizer
        self.monitorSlotResolver = monitorSlotResolver
        self.hidePointProvider = hidePointProvider
    }

    func refreshDisplayTopology() throws {
        try windowCache.updateDisplayTopology(monitorSlotResolver.topology())
    }

    func synchronizeDisplayConfiguration(
        state: inout SpaceState
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

    func applyDisplayConfiguration(
        _ discovery: WindowDiscoverySnapshot,
        state: inout SpaceState
    ) throws -> DisplayConfigurationSyncResult? {
        let previousTopology = windowCache.displayTopology
        let previousFrames = frames(for: state)
        let displayTopology = try monitorSlotResolver.topology()
        guard let sync = runtimeSynchronizer.apply(
            discovery,
            displayTopology: displayTopology,
            state: &state,
            reconcileVisibleWindowMonitorMembership: false
        ) else {
            return nil
        }
        let targetFrames = targetFramesForDisplayChange(
            from: previousTopology,
            previousFrames: previousFrames,
            state: state
        )
        return DisplayConfigurationSyncResult(sync: sync, targetFrames: targetFrames)
    }

    func targetFramesForConfiguredMonitors(state: SpaceState) -> [WindowID: WindowFrame] {
        let topology = windowCache.displayTopology
        return state.assignedWindowIDs.reduce(into: [:]) { frames, id in
            guard let space = state.membership(for: id),
                  let frame = frame(for: id, state: state)
            else {
                return
            }
            let targetSlot = state.monitorSlot(
                for: space,
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
        state: SpaceState
    ) -> [WindowID: WindowFrame] {
        let currentTopology = windowCache.displayTopology
        guard !previousTopology.monitorSlots.isEmpty,
              !currentTopology.monitorSlots.isEmpty
        else {
            return [:]
        }

        return state.assignedWindowIDs.reduce(into: [:]) { frames, id in
            guard let space = state.membership(for: id),
                  let frame = previousFrames[id]
            else {
                return
            }

            let sourceSlot = state.monitorSlot(
                for: space,
                availableMonitorSlots: previousTopology.availableMonitorSlots
            )
            let targetSlot = state.monitorSlot(
                for: space,
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
            if hidePointProvider.isHidePosition(frame, displays: previousTopology.displays) {
                frames[id] = WindowFrame(
                    origin: hidePointProvider.hidePoint(
                        for: frame,
                        on: targetDisplay,
                        among: currentTopology.displays
                    ),
                    size: frame.size
                )
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

    private func frames(for state: SpaceState) -> [WindowID: WindowFrame] {
        Dictionary(uniqueKeysWithValues: state.assignedWindowIDs.compactMap { id in
            frame(for: id, state: state).map { (id, $0) }
        })
    }

    private func frame(for id: WindowID, state: SpaceState) -> WindowFrame? {
        state.hiddenFrame(for: id) ?? windowCache.snapshot(for: id)?.frame
    }
}

struct DisplayConfigurationSyncResult {
    let sync: SpaceSyncSummary
    let targetFrames: [WindowID: WindowFrame]
}
