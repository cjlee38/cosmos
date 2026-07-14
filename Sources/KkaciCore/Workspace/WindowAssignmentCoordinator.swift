import Foundation

final class WindowAssignmentCoordinator {
    private let windowSystem: any WindowSystem
    private let configuration: WorkspaceConfigurationRuntime
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowSystem: any WindowSystem,
        configuration: WorkspaceConfigurationRuntime,
        visibilityCoordinator: WorkspaceVisibilityCoordinator,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowSystem = windowSystem
        self.configuration = configuration
        self.visibilityCoordinator = visibilityCoordinator
        self.monitorSlotResolver = monitorSlotResolver
    }

    func assignFocused(to workspace: String, state: inout WorkspaceState) throws -> WindowID {
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }

        try assignWindow(id, to: workspace, state: &state)
        return id
    }

    func assignWindow(_ id: WindowID, to workspace: String, state: inout WorkspaceState) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let previousState = state
        let previousFocusedWindowID = windowSystem.focusedWindowID()
        let previousConfig = configuration.currentConfig(workspaces: state.workspaceConfig)
        let createdWorkspace = !state.containsWorkspace(workspace.trimmingCharacters(in: .whitespacesAndNewlines))
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: workspace, state: state)
        state.assign(id, to: workspace)

        do {
            try visibilityCoordinator.applyActiveWorkspaces(
                state: &state,
                requiredWindowIDs: [id],
                targetFrames: dictionary(for: id, frame: preferredFrame)
            )
        } catch {
            try rollback(
                error,
                previousState: previousState,
                previousConfig: createdWorkspace ? previousConfig : nil,
                focusedWindowID: previousFocusedWindowID,
                state: &state
            )
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
            .filter { !$0.isMinimized && !state.isHidden($0.id) }
            .map(\.id)
        state.capture(visibleIDs, into: workspace)
    }

    func captureUnassignedVisibleWindowsByMonitor(
        _ windows: [WindowSnapshot],
        defaultWorkspace: String,
        state: inout WorkspaceState,
        monitorSlotForFrame: (WindowFrame?) -> MonitorSlot
    ) throws {
        _ = try configuration.ensureWorkspace(defaultWorkspace, state: &state)
        for window in windows where !window.isMinimized && state.membership(for: window.id) == nil {
            let workspace = state.activeWorkspace(on: monitorSlotForFrame(window.frame))
            state.capture([window.id], into: workspace)
        }
    }

    func moveFocusedWindow(
        to workspace: String,
        frontToBackWindowIDs: [WindowID],
        state: inout WorkspaceState
    ) throws -> WindowMoveResult {
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }
        guard let currentWorkspace = state.membership(for: id),
              currentWorkspace == state.activeWorkspace,
              !state.isHidden(id)
        else {
            throw WorkspaceError.windowNotInActiveWorkspace(
                id,
                state.membership(for: id) ?? state.activeWorkspace
            )
        }

        let previousState = state
        let previousFocusedWindowID = windowSystem.focusedWindowID()
        let previousConfig = configuration.currentConfig(workspaces: state.workspaceConfig)
        let createdWorkspace = !state.containsWorkspace(workspace.trimmingCharacters(in: .whitespacesAndNewlines))
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        let destinationIsActive = state.activeWorkspaces.contains(workspace)
        let replacementFocus = workspace == currentWorkspace || destinationIsActive
            ? nil
            : frontToBackWindowIDs.first { $0 != id }
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: workspace, state: state)
        state.assign(id, to: workspace)
        if destinationIsActive {
            state.activate(workspace)
        }

        do {
            try visibilityCoordinator.applyActiveWorkspaces(
                state: &state,
                focusWindowID: replacementFocus,
                requiredWindowIDs: [id],
                targetFrames: dictionary(for: id, frame: preferredFrame)
            )
            return WindowMoveResult(windowID: id, workspace: workspace)
        } catch {
            try rollback(
                error,
                previousState: previousState,
                previousConfig: createdWorkspace ? previousConfig : nil,
                focusedWindowID: previousFocusedWindowID,
                state: &state
            )
            throw error
        }
    }

    private func preferredFrameIfMovingAcrossMonitors(
        _ id: WindowID,
        to workspace: String,
        state: WorkspaceState
    ) -> WindowFrame? {
        let targetSlot = state.monitorSlot(for: workspace)
        guard let frame = state.hiddenFrame(for: id) ?? windowSystem.frame(for: id) else {
            return nil
        }
        return monitorSlotResolver.translatedFrame(frame, to: targetSlot)
    }

    private func dictionary(for id: WindowID, frame: WindowFrame?) -> [WindowID: WindowFrame] {
        guard let frame else {
            return [:]
        }
        return [id: frame]
    }

    private func rollback(
        _ applyError: Error,
        previousState: WorkspaceState,
        previousConfig: KkaciConfig?,
        focusedWindowID: WindowID?,
        state: inout WorkspaceState
    ) throws {
        var rollbackError: Error?
        if let previousConfig {
            do {
                try configuration.persist(previousConfig)
            } catch {
                rollbackError = error
            }
        }
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
