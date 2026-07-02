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

    func switchWorkspace(to workspace: String, state: inout WorkspaceState) throws {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        let previousWorkspace = state.activeWorkspace
        let oldFocusedWindow = focusedWindowInActiveWorkspace(state: state)
            ?? state.focusTarget(for: state.activeWorkspace, fallback: nil)

        state.activate(workspace)
        do {
            try visibilityCoordinator.applyActiveWorkspace(
                state: &state,
                focusActiveWorkspace: true,
                oldFocusedWindow: oldFocusedWindow,
                strictWindowIDs: Set(state.windowIDs(in: workspace))
            )
        } catch {
            state.activate(previousWorkspace)
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

        guard workspace != state.activeWorkspace else {
            state.recordFocus(id, in: workspace)
            return .alreadyActive(windowID: id, workspace: workspace)
        }

        let previousWorkspace = state.activeWorkspace
        state.recordFocus(id, in: workspace)
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
            state.activate(previousWorkspace)
            try? visibilityCoordinator.applyActiveWorkspace(state: &state)
            throw error
        }

        return .switched(windowID: id, workspace: workspace)
    }

    func focusCycledWindow(next: Bool, state: inout WorkspaceState) -> WindowFocusResult {
        let workspace = state.activeWorkspace
        let currentFocused = focusedWindowInActiveWorkspace(state: state)
        if let currentFocused {
            state.recordFocus(currentFocused, in: workspace)
        }

        let current = currentFocused ?? state.focusTarget(for: workspace, fallback: nil)
        let target = next
            ? state.nextWindow(in: workspace, after: current)
            : state.previousWindow(in: workspace, before: current)

        guard let target else {
            return .noWindowsInWorkspace(workspace)
        }

        windowSystem.focus(target)
        state.recordFocus(target, in: workspace)
        return .focused(target)
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
