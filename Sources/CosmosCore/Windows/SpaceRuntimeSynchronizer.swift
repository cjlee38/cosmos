import Foundation

final class SpaceRuntimeSynchronizer {
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
        state: inout SpaceState,
        reconcileVisibleWindowMonitorMembership: Bool = true
    ) throws -> SpaceSyncSummary {
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
        state: inout SpaceState
    ) -> SpaceSyncSummary {
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
                to: state.visibleSpace(
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

        let changes = relevantWindowIDs.sorted().compactMap { id -> SpaceMembershipChange? in
            let previousSpace = previousMemberships[id]
            let space = state.membership(for: id)
            guard previousSpace != space else {
                return nil
            }
            return SpaceMembershipChange(
                windowID: id,
                previousSpace: previousSpace?.rawValue,
                space: space?.rawValue
            )
        }
        return SpaceSyncSummary(membershipChanges: changes)
    }

    private func reconcileVisibleWindowMemberships(
        _ windows: [WindowSnapshot],
        displayTopology: DisplayTopologySnapshot,
        state: inout SpaceState
    ) {
        for window in windows where !window.isMinimized && !state.isHidden(window.id) {
            guard let space = state.membership(for: window.id),
                  let frame = window.frame
            else {
                continue
            }

            let currentSlot = monitorSlotResolver.slot(
                containing: frame,
                among: displayTopology.monitorSlots
            )
            if state.monitorSlot(
                for: space,
                availableMonitorSlots: displayTopology.availableMonitorSlots
            ) != currentSlot {
                state.assign(
                    window.id,
                    to: state.visibleSpace(
                        on: currentSlot,
                        availableMonitorSlots: displayTopology.availableMonitorSlots
                    )
                )
            }
        }
    }
}
