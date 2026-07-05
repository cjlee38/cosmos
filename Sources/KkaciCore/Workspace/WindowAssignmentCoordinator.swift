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
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: workspace, state: state)
        state.assign(id, to: workspace)

        do {
            try visibilityCoordinator.applyActiveWorkspace(
                state: &state,
                strictWindowIDs: [id],
                preferredFramesByWindowID: dictionary(for: id, frame: preferredFrame)
            )
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

    func moveFocusedWindow(to workspace: String, state: inout WorkspaceState) throws -> WindowMoveResult {
        let workspace = try configuration.ensureWorkspace(workspace, state: &state)
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let previousWorkspace = state.membership(for: id)
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: workspace, state: state)
        state.assign(id, to: workspace)

        do {
            try visibilityCoordinator.applyActiveWorkspace(
                state: &state,
                strictWindowIDs: [id],
                preferredFramesByWindowID: dictionary(for: id, frame: preferredFrame)
            )
            return WindowMoveResult(windowID: id, workspace: workspace)
        } catch {
            restoreMembership(id, to: previousWorkspace, state: &state)
            try? visibilityCoordinator.applyActiveWorkspace(state: &state)
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

    private func restoreMembership(_ id: WindowID, to workspace: String?, state: inout WorkspaceState) {
        if let workspace {
            state.assign(id, to: workspace)
        } else {
            state.unassign(id)
        }
    }
}
