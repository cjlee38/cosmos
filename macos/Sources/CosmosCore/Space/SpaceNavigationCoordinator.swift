import Foundation

final class SpaceNavigationCoordinator {
    private let windowCache: WindowStateCache
    private let visibilityCoordinator: SpaceVisibilityCoordinator

    init(
        windowCache: WindowStateCache,
        visibilityCoordinator: SpaceVisibilityCoordinator
    ) {
        self.windowCache = windowCache
        self.visibilityCoordinator = visibilityCoordinator
    }

    func switchSpace(
        to space: SpaceID,
        frontToBackWindowIDs: [WindowID],
        state: inout SpaceState
    ) throws {
        let previousState = state
        let previouslyVisibleSpaces = visibleSpaces(in: state)
        let oldFocusedWindow = focusedWindowInCurrentSpace(state: state)
            ?? firstWindow(in: state.currentSpace, from: frontToBackWindowIDs, state: state)
        let preferredFocus = firstWindow(in: space, from: frontToBackWindowIDs, state: state)

        state.activate(space)
        do {
            let requiredWindowIDs = requiredVisibilityWindowIDs(
                destination: space,
                previouslyVisibleSpaces: previouslyVisibleSpaces,
                state: state
            )
            try visibilityCoordinator.applyVisibleSpaces(
                state: &state,
                focusWindowID: preferredFocus,
                hideLastWindowID: oldFocusedWindow,
                mustSucceedWindowIDs: requiredWindowIDs
            )
        } catch {
            try visibilityCoordinator.rollback(
                after: error,
                to: previousState,
                focusedWindowID: oldFocusedWindow,
                state: &state
            )
            throw error
        }
    }

    func syncSpaceToFocusedWindow(
        frontToBackWindowIDs: [WindowID],
        targetFrames: [WindowID: WindowFrame] = [:],
        state: inout SpaceState
    ) throws -> FocusedWindowSpaceSyncResult {
        guard let id = windowCache.focusedWindowID else {
            return .noFocusedWindow
        }

        guard windowCache.snapshot(for: id) != nil,
              let space = state.membership(for: id)
        else {
            return .unmanagedWindow(id)
        }

        let availableMonitorSlots = windowCache.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: space,
            availableMonitorSlots: availableMonitorSlots
        )
        guard space != state.visibleSpace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        ) else {
            state.activate(space)
            return .alreadyActive(windowID: id, space: space.rawValue)
        }

        let previousState = state
        let previouslyVisibleSpaces = visibleSpaces(in: state)
        let rollbackFocus = firstWindow(
            in: previousState.currentSpace,
            from: frontToBackWindowIDs,
            state: previousState
        )
        state.activate(space)
        do {
            let requiredWindowIDs = requiredVisibilityWindowIDs(
                destination: space,
                previouslyVisibleSpaces: previouslyVisibleSpaces,
                state: state
            )
            try visibilityCoordinator.applyVisibleSpaces(
                state: &state,
                focusWindowID: id,
                mustSucceedWindowIDs: requiredWindowIDs,
                targetFrames: targetFrames
            )
        } catch {
            try visibilityCoordinator.rollback(
                after: error,
                to: previousState,
                focusedWindowID: rollbackFocus,
                state: &state
            )
            throw error
        }

        return .switched(windowID: id, space: space.rawValue)
    }

    private func firstWindow(
        in space: SpaceID,
        from frontToBackWindowIDs: [WindowID],
        state: SpaceState
    ) -> WindowID? {
        frontToBackWindowIDs.first { state.membership(for: $0) == space }
    }

    private func focusedWindowInCurrentSpace(state: SpaceState) -> WindowID? {
        guard let id = windowCache.focusedWindowID,
              state.membership(for: id) == state.currentSpace
        else {
            return nil
        }
        return id
    }

    private func requiredVisibilityWindowIDs(
        destination: SpaceID,
        previouslyVisibleSpaces: Set<SpaceID>,
        state: SpaceState
    ) -> Set<WindowID> {
        let newlyHiddenSpaces = previouslyVisibleSpaces.subtracting(visibleSpaces(in: state))
        return Set(state.windowIDs(in: destination)).union(
            newlyHiddenSpaces.flatMap(state.windowIDs(in:))
        )
    }

    private func visibleSpaces(in state: SpaceState) -> Set<SpaceID> {
        state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
    }
}
