import Foundation

final class WorkspaceNavigationCoordinator {
    private let windowSystem: any WindowSystem
    private let configuration: WorkspaceConfigurationRuntime
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator

    init(
        windowSystem: any WindowSystem,
        configuration: WorkspaceConfigurationRuntime,
        visibilityCoordinator: WorkspaceVisibilityCoordinator
    ) {
        self.windowSystem = windowSystem
        self.configuration = configuration
        self.visibilityCoordinator = visibilityCoordinator
    }

    func switchWorkspace(
        to workspace: String,
        frontToBackWindowIDs: [WindowID],
        state: inout WorkspaceState
    ) throws {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        let previousActivation = state.activationSnapshot
        let oldFocusedWindow = focusedWindowInActiveWorkspace(state: state)
            ?? firstWindow(in: state.activeWorkspace, from: frontToBackWindowIDs, state: state)
        let preferredFocus = firstWindow(in: workspace, from: frontToBackWindowIDs, state: state)

        state.activate(workspace)
        do {
            try visibilityCoordinator.applyActiveWorkspace(
                state: &state,
                focusActiveWorkspace: true,
                preferredFocus: preferredFocus,
                oldFocusedWindow: oldFocusedWindow,
                strictWindowIDs: Set(state.windowIDs(in: workspace))
            )
        } catch {
            state.restoreActivationSnapshot(previousActivation)
            try? visibilityCoordinator.applyActiveWorkspace(state: &state)
            throw error
        }
    }

    func syncWorkspaceToFocusedWindow(state: inout WorkspaceState) throws -> FocusedWindowWorkspaceSyncResult {
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

        let previousActivation = state.activationSnapshot
        state.activate(workspace)
        do {
            try visibilityCoordinator.applyActiveWorkspace(
                state: &state,
                focusActiveWorkspace: true,
                preferredFocus: id,
                oldFocusedWindow: nil,
                strictWindowIDs: [id]
            )
        } catch {
            state.restoreActivationSnapshot(previousActivation)
            try? visibilityCoordinator.applyActiveWorkspace(state: &state)
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
        let current = currentFocused ?? frontToBackWindowIDs.first
        let direction: CycleDirection = next ? .forward : .backward
        let target = cycledValue(in: frontToBackWindowIDs, after: current, direction: direction)

        guard let target else {
            return .noWindowsInWorkspace(workspace)
        }

        windowSystem.focus(target)
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
}
