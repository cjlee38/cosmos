import Foundation

final class WindowAssignmentCoordinator {
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

    func assignFocused(to workspace: String, state: inout WorkspaceState) throws -> WindowID {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }

        try assignWindow(id, to: workspace, state: &state)
        return id
    }

    func assignWindow(_ id: WindowID, to workspace: String, state: inout WorkspaceState) throws {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let previousWorkspace = state.membership(for: id)
        state.assign(id, to: workspace)

        do {
            try visibilityCoordinator.applyActiveWorkspace(state: &state, strictWindowIDs: [id])
        } catch {
            restoreMembership(id, to: previousWorkspace, state: &state)
            try? visibilityCoordinator.applyActiveWorkspace(state: &state)
            throw error
        }
    }

    func captureVisibleWindows(
        _ windows: [WindowSnapshot],
        into workspace: String,
        state: inout WorkspaceState
    ) throws {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        let visibleIDs = windows
            .filter { !$0.isMinimized }
            .map(\.id)
        state.capture(visibleIDs, into: workspace)
    }

    func captureUnassignedVisibleWindows(
        _ windows: [WindowSnapshot],
        into workspace: String,
        state: inout WorkspaceState
    ) throws {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        let visibleIDs = windows
            .filter { !$0.isMinimized && state.membership(for: $0.id) == nil }
            .map(\.id)
        state.capture(visibleIDs, into: workspace)
    }

    func moveFocusedWindow(to workspace: String, state: inout WorkspaceState) throws -> WindowMoveResult {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let previousWorkspace = state.membership(for: id)
        state.assign(id, to: workspace)

        do {
            try visibilityCoordinator.applyActiveWorkspace(state: &state, strictWindowIDs: [id])
            return WindowMoveResult(windowID: id, workspace: workspace)
        } catch {
            restoreMembership(id, to: previousWorkspace, state: &state)
            try? visibilityCoordinator.applyActiveWorkspace(state: &state)
            throw error
        }
    }

    private func restoreMembership(_ id: WindowID, to workspace: String?, state: inout WorkspaceState) {
        if let workspace {
            state.assign(id, to: workspace)
        } else {
            state.unassign(id)
        }
    }
}
