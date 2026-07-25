import Foundation

final class WindowAssignmentCoordinator {
    private let windowCache: WindowStateCache
    private let visibilityCoordinator: SpaceVisibilityCoordinator
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowCache: WindowStateCache,
        visibilityCoordinator: SpaceVisibilityCoordinator,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowCache = windowCache
        self.visibilityCoordinator = visibilityCoordinator
        self.monitorSlotResolver = monitorSlotResolver
    }

    func moveFocusedWindow(
        to space: SpaceID,
        frontToBackWindowIDs: [WindowID],
        state: inout SpaceState
    ) throws -> WindowMoveResult {
        let (id, currentSpace) = try focusedWindowForMove(state: state)
        guard currentSpace != space else {
            return WindowMoveResult(
                windowID: id,
                previousSpace: currentSpace.rawValue,
                space: space.rawValue,
                outcome: .alreadyInSpace
            )
        }

        let previousState = state
        let previousFocusedWindowID = windowCache.focusedWindowID
        let destinationIsVisible = state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        ).contains(space)
        let replacementFocus = destinationIsVisible
            ? nil
            : frontToBackWindowIDs.first { $0 != id }
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: space, state: state)
        state.assign(id, to: space)
        if destinationIsVisible {
            state.activate(space)
        }

        do {
            try visibilityCoordinator.applyVisibleSpaces(
                state: &state,
                focusWindowID: replacementFocus,
                mustSucceedWindowIDs: [id],
                targetFrames: preferredFrame.map { [id: $0] } ?? [:]
            )
            return WindowMoveResult(
                windowID: id,
                previousSpace: currentSpace.rawValue,
                space: space.rawValue,
                outcome: .moved
            )
        } catch {
            try visibilityCoordinator.rollback(
                after: error,
                to: previousState,
                focusedWindowID: previousFocusedWindowID,
                state: &state
            )
            throw error
        }
    }

    private func focusedWindowForMove(state: SpaceState) throws -> (WindowID, SpaceID) {
        guard let id = windowCache.focusedWindowID else {
            throw SpaceError.noFocusedWindow
        }
        guard windowCache.snapshot(for: id) != nil else {
            throw SpaceError.windowNotFound(id)
        }
        guard let space = state.membership(for: id),
              space == state.currentSpace,
              !state.isHidden(id)
        else {
            throw SpaceError.windowNotInCurrentSpace(
                id,
                (state.membership(for: id) ?? state.currentSpace).rawValue
            )
        }
        return (id, space)
    }

    private func preferredFrameIfMovingAcrossMonitors(
        _ id: WindowID,
        to space: SpaceID,
        state: SpaceState
    ) -> WindowFrame? {
        let monitorSlots = windowCache.displayTopology.monitorSlots
        let targetSlot = state.monitorSlot(
            for: space,
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
        guard let frame = state.hiddenFrame(for: id) ?? windowCache.snapshot(for: id)?.frame else {
            return nil
        }
        let sourceSlot = monitorSlotResolver.slot(containing: frame, among: monitorSlots)
        guard sourceSlot != targetSlot else {
            return nil
        }
        return monitorSlotResolver.translatedFrame(frame, to: targetSlot, among: monitorSlots)
    }
}
