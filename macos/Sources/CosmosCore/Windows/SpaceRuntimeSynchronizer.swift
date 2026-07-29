import Foundation

final class SpaceRuntimeSynchronizer {
    private let windowSystem: any WindowSystem
    private let windowCache: WindowStateCache
    private let recordRepository: HiddenWindowRecordRepository
    private let monitorSlotResolver: MonitorSlotResolver
    private let hidePointProvider: any HidePointProviding
    private let continuityProtector = WindowContinuityProtector()

    init(
        windowSystem: any WindowSystem,
        windowCache: WindowStateCache,
        recordRepository: HiddenWindowRecordRepository,
        monitorSlotResolver: MonitorSlotResolver,
        hidePointProvider: any HidePointProviding
    ) {
        self.windowSystem = windowSystem
        self.windowCache = windowCache
        self.recordRepository = recordRepository
        self.monitorSlotResolver = monitorSlotResolver
        self.hidePointProvider = hidePointProvider
    }

    func beginContinuityProtection(state: SpaceState) {
        continuityProtector.capture(
            windows: windowCache.windows,
            topology: windowCache.displayTopology,
            state: state,
            phase: .beforeDiscovery
        )
    }

    var continuityProtectedWindowIDs: Set<WindowID> {
        continuityProtector.protectedWindowIDs
    }

    var continuityRecoveryPlan: WindowContinuityRecoveryPlan {
        continuityProtector.recoveryPlan
    }

    func completeContinuityRecovery(windowIDs: Set<WindowID>) {
        continuityProtector.completeRecovery(windowIDs: windowIDs)
    }

    func cancelContinuityRecovery(windowIDs: Set<WindowID>) {
        continuityProtector.cancel(windowIDs: windowIDs)
    }

    func synchronize(
        state: inout SpaceState,
        reconcileVisibleWindowMonitorMembership: Bool = true,
        detectDisplayContinuityLoss: Bool = false,
        lifecycle: WindowLifecycleConfirmation = .empty
    ) throws -> SpaceSyncSummary {
        while true {
            let discovery = try windowSystem.discover(windowIDs: nil, mode: .normal)
            let displayTopology = try monitorSlotResolver.topology()
            guard windowSystem.apply(discovery) else {
                continue
            }
            return synchronizeAcceptedDiscovery(
                discovery,
                displayTopology: displayTopology,
                policy: SpaceSynchronizationPolicy(
                    reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership,
                    detectDisplayContinuityLoss: detectDisplayContinuityLoss,
                    lifecycle: lifecycle
                ),
                state: &state
            )
        }
    }

    func apply(
        _ discovery: WindowDiscoverySnapshot,
        displayTopology: DisplayTopologySnapshot,
        state: inout SpaceState,
        reconcileVisibleWindowMonitorMembership: Bool = true,
        detectDisplayContinuityLoss: Bool = false,
        lifecycle: WindowLifecycleConfirmation = .empty
    ) -> SpaceSyncSummary? {
        guard windowSystem.apply(discovery) else {
            return nil
        }
        return synchronizeAcceptedDiscovery(
            discovery,
            displayTopology: displayTopology,
            policy: SpaceSynchronizationPolicy(
                reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership,
                detectDisplayContinuityLoss: detectDisplayContinuityLoss,
                lifecycle: lifecycle
            ),
            state: &state
        )
    }

    private func synchronizeAcceptedDiscovery(
        _ discovery: WindowDiscoverySnapshot,
        displayTopology: DisplayTopologySnapshot,
        policy: SpaceSynchronizationPolicy,
        state: inout SpaceState
    ) -> SpaceSyncSummary {
        if policy.detectDisplayContinuityLoss {
            continuityProtector.captureIfDisplayContinuityWasLost(
                previousTopology: windowCache.displayTopology,
                currentTopology: displayTopology,
                windows: windowCache.windows,
                state: state
            )
        }
        return synchronizeAppliedDiscovery(
            discovery,
            displayTopology: displayTopology,
            reconcileVisibleWindowMonitorMembership: policy.reconcileVisibleWindowMonitorMembership,
            lifecycle: policy.lifecycle,
            state: &state
        )
    }

    private func synchronizeAppliedDiscovery(
        _ discovery: WindowDiscoverySnapshot,
        displayTopology: DisplayTopologySnapshot,
        reconcileVisibleWindowMonitorMembership: Bool,
        lifecycle: WindowLifecycleConfirmation,
        state: inout SpaceState
    ) -> SpaceSyncSummary {
        let protection = continuityProtector.resolve(
            with: discovery,
            lifecycle: lifecycle
        )
        let windowSetDiff = windowCache.apply(
            discovery,
            displayTopology: displayTopology
        )
        windowCache.remove(protection.suppressedDiscoveredWindowIDs)
        let windows = windowCache.windows
        let removedWindowIDs = Set(windowSetDiff.removed)
            .subtracting(protection.protectedWindowIDs)
            .union(protection.confirmedRemovedWindowIDs)
        let sync = synchronizeMemberships(
            windows: windows,
            removedWindowIDs: removedWindowIDs,
            displayTopology: displayTopology,
            reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership,
            excludedWindowIDs: protection.protectedWindowIDs,
            state: &state
        )
        for id in removedWindowIDs {
            recordRepository.removeAllRecords(for: id)
        }

        return sync
    }

    private func synchronizeMemberships(
        windows: [WindowSnapshot],
        removedWindowIDs: Set<WindowID>,
        displayTopology: DisplayTopologySnapshot,
        reconcileVisibleWindowMonitorMembership: Bool,
        excludedWindowIDs: Set<WindowID>,
        state: inout SpaceState
    ) -> SpaceSyncSummary {
        let liveWindowIDs = Set(windows.map(\.id))
        let relevantWindowIDs = liveWindowIDs.union(removedWindowIDs)
        let previousMemberships = Dictionary(uniqueKeysWithValues: relevantWindowIDs.compactMap { id in
            state.membership(for: id).map { (id, $0) }
        })

        for id in removedWindowIDs {
            state.removeWindow(id)
        }

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
                excludedWindowIDs: excludedWindowIDs,
                state: &state
            )
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
        excludedWindowIDs: Set<WindowID>,
        state: inout SpaceState
    ) {
        for window in windows
            where !window.isMinimized
            && !state.isHidden(window.id)
            && !excludedWindowIDs.contains(window.id) {
            guard let space = state.membership(for: window.id),
                  let frame = window.frame,
                  !hidePointProvider.isHidePosition(
                      frame,
                      displays: displayTopology.displays
                  )
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

private struct SpaceSynchronizationPolicy {
    let reconcileVisibleWindowMonitorMembership: Bool
    let detectDisplayContinuityLoss: Bool
    let lifecycle: WindowLifecycleConfirmation
}
