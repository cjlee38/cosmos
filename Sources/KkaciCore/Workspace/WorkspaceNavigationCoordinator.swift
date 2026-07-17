import Foundation

final class WorkspaceNavigationCoordinator {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator

    init(
        windowSystem: any WindowSystem,
        windowStore: WindowRuntimeStore,
        visibilityCoordinator: WorkspaceVisibilityCoordinator
    ) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
        self.visibilityCoordinator = visibilityCoordinator
    }

    func switchWorkspace(
        to workspace: String,
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
                requiredWindowIDs: requiredWindowIDs
            )
        } catch {
            try rollback(
                error,
                previousState: previousState,
                focusedWindowID: oldFocusedWindow,
                state: &state
            )
            throw error
        }
    }

    func syncWorkspaceToFocusedWindow(
        frontToBackWindowIDs: [WindowID],
        state: inout WorkspaceState
    ) throws -> FocusedWindowWorkspaceSyncResult {
        guard let id = windowSystem.focusedWindowID() else {
            return .noFocusedWindow
        }

        guard windowSystem.contains(id),
              let workspace = state.membership(for: id)
        else {
            return .unmanagedWindow(id)
        }

        let availableMonitorSlots = windowStore.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
        guard workspace != state.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        ) else {
            state.activate(workspace)
            return .alreadyActive(windowID: id, workspace: workspace)
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
                requiredWindowIDs: requiredWindowIDs
            )
        } catch {
            try rollback(
                error,
                previousState: previousState,
                focusedWindowID: rollbackFocus,
                state: &state
            )
            throw error
        }

        return .switched(windowID: id, workspace: workspace)
    }

    func focusCycledWindow(
        next: Bool,
        frontToBackWindowIDs: [WindowID],
        state: WorkspaceState
    ) -> WindowFocusResult {
        let workspace = state.currentWorkspace
        let currentFocused = focusedWindowInCurrentWorkspace(state: state)
        let direction: CycleDirection = next ? .forward : .backward
        let target = currentFocused.map { current in
            cycledValue(in: frontToBackWindowIDs, after: current, direction: direction)
        } ?? (next ? frontToBackWindowIDs.first : frontToBackWindowIDs.last)

        guard let target else {
            return .noWindowsInWorkspace(workspace)
        }

        windowSystem.focus(target)
        windowStore.updateFocusedWindowID(target)
        return .focused(target)
    }

    private func firstWindow(
        in workspace: String,
        from frontToBackWindowIDs: [WindowID],
        state: WorkspaceState
    ) -> WindowID? {
        frontToBackWindowIDs.first { state.membership(for: $0) == workspace }
    }

    private func focusedWindowInCurrentWorkspace(state: WorkspaceState) -> WindowID? {
        guard let id = windowSystem.focusedWindowID(),
              state.membership(for: id) == state.currentWorkspace
        else {
            return nil
        }
        return id
    }

    private func requiredVisibilityWindowIDs(
        destination: String,
        previouslyVisibleWorkspaces: Set<String>,
        state: WorkspaceState
    ) -> Set<WindowID> {
        let newlyHiddenWorkspaces = previouslyVisibleWorkspaces.subtracting(visibleWorkspaces(in: state))
        return Set(state.windowIDs(in: destination)).union(
            newlyHiddenWorkspaces.flatMap(state.windowIDs(in:))
        )
    }

    private func visibleWorkspaces(in state: WorkspaceState) -> Set<String> {
        state.visibleWorkspaces(
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
    }

    private func rollback(
        _ applyError: Error,
        previousState: WorkspaceState,
        focusedWindowID: WindowID?,
        state: inout WorkspaceState
    ) throws {
        var rollbackError: Error?
        do {
            try visibilityCoordinator.rollback(
                to: previousState,
                focusedWindowID: focusedWindowID,
                state: &state
            )
        } catch {
            rollbackError = rollbackError ?? error
        }
        if let rollbackError {
            throw WorkspaceTransactionError(
                applyError: applyError,
                rollbackError: rollbackError
            )
        }
    }
}
