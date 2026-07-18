import Foundation

final class WorkspaceNavigationCoordinator {
    private let windowCache: WindowStateCache
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator

    init(
        windowCache: WindowStateCache,
        visibilityCoordinator: WorkspaceVisibilityCoordinator
    ) {
        self.windowCache = windowCache
        self.visibilityCoordinator = visibilityCoordinator
    }

    func switchWorkspace(
        to workspace: WorkspaceID,
        frontToBackWindowIDs: [WindowID],
        state: inout WorkspaceState
    ) throws {
        let previousState = state
        let previouslyVisibleWorkspaces = visibleWorkspaces(in: state)
        let oldFocusedWindow = focusedWindowInCurrentWorkspace(state: state)
            ?? firstWindow(in: state.currentWorkspace, from: frontToBackWindowIDs, state: state)
        let preferredFocus = firstWindow(in: workspace, from: frontToBackWindowIDs, state: state)

        state.activate(workspace)
        do {
            let requiredWindowIDs = requiredVisibilityWindowIDs(
                destination: workspace,
                previouslyVisibleWorkspaces: previouslyVisibleWorkspaces,
                state: state
            )
            try visibilityCoordinator.applyVisibleWorkspaces(
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

    func syncWorkspaceToFocusedWindow(
        frontToBackWindowIDs: [WindowID],
        targetFrames: [WindowID: WindowFrame] = [:],
        state: inout WorkspaceState
    ) throws -> FocusedWindowWorkspaceSyncResult {
        guard let id = windowCache.focusedWindowID else {
            return .noFocusedWindow
        }

        guard windowCache.snapshot(for: id) != nil,
              let workspace = state.membership(for: id)
        else {
            return .unmanagedWindow(id)
        }

        let availableMonitorSlots = windowCache.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
        guard workspace != state.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        ) else {
            state.activate(workspace)
            return .alreadyActive(windowID: id, workspace: workspace.rawValue)
        }

        let previousState = state
        let previouslyVisibleWorkspaces = visibleWorkspaces(in: state)
        let rollbackFocus = firstWindow(
            in: previousState.currentWorkspace,
            from: frontToBackWindowIDs,
            state: previousState
        )
        state.activate(workspace)
        do {
            let requiredWindowIDs = requiredVisibilityWindowIDs(
                destination: workspace,
                previouslyVisibleWorkspaces: previouslyVisibleWorkspaces,
                state: state
            )
            try visibilityCoordinator.applyVisibleWorkspaces(
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

        return .switched(windowID: id, workspace: workspace.rawValue)
    }

    private func firstWindow(
        in workspace: WorkspaceID,
        from frontToBackWindowIDs: [WindowID],
        state: WorkspaceState
    ) -> WindowID? {
        frontToBackWindowIDs.first { state.membership(for: $0) == workspace }
    }

    private func focusedWindowInCurrentWorkspace(state: WorkspaceState) -> WindowID? {
        guard let id = windowCache.focusedWindowID,
              state.membership(for: id) == state.currentWorkspace
        else {
            return nil
        }
        return id
    }

    private func requiredVisibilityWindowIDs(
        destination: WorkspaceID,
        previouslyVisibleWorkspaces: Set<WorkspaceID>,
        state: WorkspaceState
    ) -> Set<WindowID> {
        let newlyHiddenWorkspaces = previouslyVisibleWorkspaces.subtracting(visibleWorkspaces(in: state))
        return Set(state.windowIDs(in: destination)).union(
            newlyHiddenWorkspaces.flatMap(state.windowIDs(in:))
        )
    }

    private func visibleWorkspaces(in state: WorkspaceState) -> Set<WorkspaceID> {
        state.visibleWorkspaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
    }
}
