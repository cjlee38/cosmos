import Foundation

final class SpaceExternalWindowChangeCoordinator {
    private let windowCache: WindowStateCache
    private let runtimeSynchronizer: SpaceRuntimeSynchronizer
    private let hiddenWindowOperator: HiddenWindowOperator
    private let visibilityCoordinator: SpaceVisibilityCoordinator
    private let navigationCoordinator: SpaceNavigationCoordinator
    private let displayCoordinator: SpaceDisplayCoordinator

    init(
        windowCache: WindowStateCache,
        runtimeSynchronizer: SpaceRuntimeSynchronizer,
        hiddenWindowOperator: HiddenWindowOperator,
        visibilityCoordinator: SpaceVisibilityCoordinator,
        navigationCoordinator: SpaceNavigationCoordinator,
        displayCoordinator: SpaceDisplayCoordinator
    ) {
        self.windowCache = windowCache
        self.runtimeSynchronizer = runtimeSynchronizer
        self.hiddenWindowOperator = hiddenWindowOperator
        self.visibilityCoordinator = visibilityCoordinator
        self.navigationCoordinator = navigationCoordinator
        self.displayCoordinator = displayCoordinator
    }

    func handle(
        _ change: ExternalWindowChange,
        state: inout SpaceState
    ) throws -> ExternalWindowEventResult {
        runtimeSynchronizer.cancelContinuityRecovery(windowIDs: change.userMovedWindowIDs)
        let lifecycle = lifecycleConfirmation(for: change)
        let sync: SpaceSyncSummary
        let targetFrames: [WindowID: WindowFrame]
        if change.displayConfigurationChanged {
            let displaySync = try displayCoordinator.synchronizeDisplayConfiguration(
                lifecycle: lifecycle,
                state: &state
            )
            sync = displaySync.sync
            targetFrames = displaySync.targetFrames
        } else {
            sync = try runtimeSynchronizer.synchronize(
                state: &state,
                lifecycle: lifecycle
            )
            targetFrames = [:]
        }
        return try recoverAndFinish(
            change,
            sync: sync,
            targetFrames: targetFrames,
            state: &state
        )
    }

    func apply(
        _ change: ExternalWindowChange,
        discovery: WindowDiscoverySnapshot,
        state: inout SpaceState
    ) throws -> ExternalWindowEventResult? {
        runtimeSynchronizer.cancelContinuityRecovery(windowIDs: change.userMovedWindowIDs)
        let lifecycle = lifecycleConfirmation(for: change)
        let sync: SpaceSyncSummary
        let targetFrames: [WindowID: WindowFrame]
        if change.displayConfigurationChanged {
            guard let displaySync = try displayCoordinator.applyDisplayConfiguration(
                discovery,
                lifecycle: lifecycle,
                state: &state
            ) else {
                return nil
            }
            sync = displaySync.sync
            targetFrames = displaySync.targetFrames
        } else {
            guard let appliedSync = runtimeSynchronizer.apply(
                discovery,
                displayTopology: windowCache.displayTopology,
                state: &state,
                lifecycle: lifecycle
            ) else {
                return nil
            }
            sync = appliedSync
            targetFrames = [:]
        }
        return try recoverAndFinish(
            change,
            sync: sync,
            targetFrames: targetFrames,
            state: &state
        )
    }

    private func recoverAndFinish(
        _ change: ExternalWindowChange,
        sync: SpaceSyncSummary,
        targetFrames: [WindowID: WindowFrame],
        state: inout SpaceState
    ) throws -> ExternalWindowEventResult {
        let eligibleWindowIDs = runtimeSynchronizer.continuityEligibleWindowIDs
        let recovery = visibilityCoordinator.applyContinuityRecovery(
            windowIDs: eligibleWindowIDs,
            targetFrames: displayCoordinator.continuityRecoveryTargetFrames(state: state),
            state: &state
        )
        let result = try finish(
            change,
            sync: sync,
            targetFrames: targetFrames,
            excludedWindowIDs: runtimeSynchronizer.continuityProtectedWindowIDs,
            state: &state
        )
        runtimeSynchronizer.completeContinuityRecovery(
            windowIDs: recovery.succeededWindowIDs
        )
        return ExternalWindowEventResult(
            sync: result.sync,
            focusedWindowSync: result.focusedWindowSync,
            continuityRecovery: WindowContinuityRecoveryStatus(
                pendingWindowIDs: runtimeSynchronizer.continuityProtectedWindowIDs,
                failedWindowIDs: recovery.failedWindowIDs,
                attempts: recovery.attempts
            )
        )
    }

    private func lifecycleConfirmation(
        for change: ExternalWindowChange
    ) -> WindowLifecycleConfirmation {
        WindowLifecycleConfirmation(
            terminatedApplicationPIDs: change.terminatedApplicationPIDs,
            destroyedWindowIDs: change.displayConfigurationChanged ? [] : change.destroyedWindowIDs
        )
    }

    private func finish(
        _ change: ExternalWindowChange,
        sync: SpaceSyncSummary,
        targetFrames initialTargetFrames: [WindowID: WindowFrame],
        excludedWindowIDs: Set<WindowID>,
        state: inout SpaceState
    ) throws -> ExternalWindowEventResult {
        var targetFrames = initialTargetFrames
        let shouldFollowFocusedWindow = change.focusPolicy.shouldFollow(
            focusedWindowID: windowCache.focusedWindowID,
            state: state
        ) && windowCache.focusedWindowID.map {
            !excludedWindowIDs.contains($0)
        } ?? true
        if shouldFollowFocusedWindow,
           let id = windowCache.focusedWindowID,
           let targetFrame = targetFrames[id],
           try recoverFocusedWindowParking(id, referenceFrame: targetFrame, state: state) {
            targetFrames.removeValue(forKey: id)
        }
        let focusedWindowSync = try synchronizeFocusedWindow(
            shouldFollow: shouldFollowFocusedWindow,
            targetFrames: targetFrames,
            excludedWindowIDs: excludedWindowIDs,
            state: &state
        )
        if shouldFollowFocusedWindow, let id = windowCache.focusedWindowID {
            try restoreFocusedWindow(id, state: &state)
        }
        return ExternalWindowEventResult(sync: sync, focusedWindowSync: focusedWindowSync)
    }

    private func synchronizeFocusedWindow(
        shouldFollow: Bool,
        targetFrames: [WindowID: WindowFrame],
        excludedWindowIDs: Set<WindowID>,
        state: inout SpaceState
    ) throws -> FocusedWindowSpaceSyncResult? {
        guard shouldFollow else {
            try visibilityCoordinator.applyVisibleSpaces(
                state: &state,
                excludedWindowIDs: excludedWindowIDs,
                targetFrames: targetFrames
            )
            return nil
        }
        let result = try navigationCoordinator.syncSpaceToFocusedWindow(
            frontToBackWindowIDs: windowCache.windows.filter { !$0.isMinimized }.map(\.id),
            targetFrames: targetFrames,
            state: &state
        )
        switch result {
        case .switched:
            break
        case .alreadyActive, .noFocusedWindow, .unmanagedWindow:
            try visibilityCoordinator.applyVisibleSpaces(
                state: &state,
                excludedWindowIDs: excludedWindowIDs,
                targetFrames: targetFrames
            )
        }
        return result
    }

    private func recoverFocusedWindowParking(
        _ id: WindowID,
        referenceFrame: WindowFrame,
        state: SpaceState
    ) throws -> Bool {
        guard let visibleFrame = visibleFrameForWindowSpace(id, state: state) else {
            return false
        }
        return try hiddenWindowOperator.recoverParkingPositionForFocus(
            id,
            referenceFrame: referenceFrame,
            fallbackVisibleFrame: visibleFrame,
            displays: windowCache.displayTopology.displays,
            state: state
        )
    }

    private func restoreFocusedWindow(_ id: WindowID, state: inout SpaceState) throws {
        guard state.membership(for: id) != nil else {
            return
        }
        guard let visibleFrame = visibleFrameForWindowSpace(id, state: state) else {
            throw SpaceError.noDisplayAvailable
        }
        try hiddenWindowOperator.restoreForFocus(
            id,
            fallbackVisibleFrame: visibleFrame,
            displays: windowCache.displayTopology.displays,
            state: &state
        )
    }

    private func visibleFrameForWindowSpace(_ id: WindowID, state: SpaceState) -> CGRect? {
        guard let space = state.membership(for: id) else {
            return nil
        }
        let availableMonitorSlots = windowCache.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: space,
            availableMonitorSlots: availableMonitorSlots
        )
        return windowCache.displayTopology.monitorSlots.first(
            where: { $0.slot == monitorSlot }
        )?.display.visibleFrame
    }
}

private extension ExternalWindowFocusPolicy {
    func shouldFollow(focusedWindowID: WindowID?, state: SpaceState) -> Bool {
        switch self {
        case .never:
            false
        case .always:
            true
        case .visibleFocusedWindow:
            focusedWindowID.map { !state.isHidden($0) } ?? false
        }
    }
}
