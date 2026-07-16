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
        let previouslyActiveWorkspaces = state.activeWorkspaces
        let oldFocusedWindow = focusedWindowInActiveWorkspace(state: state)
            ?? firstWindow(in: state.activeWorkspace, from: frontToBackWindowIDs, state: state)
        let preferredFocus = firstWindow(in: workspace, from: frontToBackWindowIDs, state: state)

        state.activate(workspace)
        do {
            let requiredWindowIDs = requiredVisibilityWindowIDs(
                destination: workspace,
                previouslyActiveWorkspaces: previouslyActiveWorkspaces,
                state: state
            )
            try visibilityCoordinator.applyActiveWorkspaces(
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

        let monitorSlot = state.monitorSlot(for: workspace)
        guard workspace != state.activeWorkspace(on: monitorSlot) else {
            state.activate(workspace)
            return .alreadyActive(windowID: id, workspace: workspace)
        }

        let previousState = state
        let previouslyActiveWorkspaces = state.activeWorkspaces
        let rollbackFocus = firstWindow(
            in: previousState.activeWorkspace,
            from: frontToBackWindowIDs,
            state: previousState
        )
        state.activate(workspace)
        do {
            let requiredWindowIDs = requiredVisibilityWindowIDs(
                destination: workspace,
                previouslyActiveWorkspaces: previouslyActiveWorkspaces,
                state: state
            )
            try visibilityCoordinator.applyActiveWorkspaces(
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
        let workspace = state.activeWorkspace
        let currentFocused = focusedWindowInActiveWorkspace(state: state)
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

    private func focusedWindowInActiveWorkspace(state: WorkspaceState) -> WindowID? {
        guard let id = windowSystem.focusedWindowID(),
              state.membership(for: id) == state.activeWorkspace
        else {
            return nil
        }
        return id
    }

    private func requiredVisibilityWindowIDs(
        destination: String,
        previouslyActiveWorkspaces: Set<String>,
        state: WorkspaceState
    ) -> Set<WindowID> {
        let deactivatedWorkspaces = previouslyActiveWorkspaces.subtracting(state.activeWorkspaces)
        return Set(state.windowIDs(in: destination)).union(
            deactivatedWorkspaces.flatMap(state.windowIDs(in:))
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
