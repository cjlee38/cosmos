import Foundation

final class WindowAssignmentCoordinator {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowSystem: any WindowSystem,
        windowStore: WindowRuntimeStore,
        visibilityCoordinator: WorkspaceVisibilityCoordinator,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowSystem = windowSystem
        self.windowStore = windowStore
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
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: workspace, state: state)
        state.assign(id, to: workspace)

        do {
            try visibilityCoordinator.applyVisibleWorkspaces(
                state: &state,
                requiredWindowIDs: [id],
                targetFrames: dictionary(for: id, frame: preferredFrame)
            )
        } catch {
            try rollback(
                error,
                previousState: previousState,
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
    ) {
        guard state.findWorkspace(defaultWorkspace) != nil else {
            return
        }
        for window in windows where !window.isMinimized && state.membership(for: window.id) == nil {
            let workspace = state.visibleWorkspace(
                on: monitorSlotForFrame(window.frame),
                availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
            )
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
              currentWorkspace == state.currentWorkspace,
              !state.isHidden(id)
        else {
            throw WorkspaceError.windowNotInCurrentWorkspace(
                id,
                state.membership(for: id) ?? state.currentWorkspace
            )
        }

        let previousState = state
        let previousFocusedWindowID = windowSystem.focusedWindowID()
        let destinationIsVisible = state.visibleWorkspaces(
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        ).contains(workspace)
        let replacementFocus = workspace == currentWorkspace || destinationIsVisible
            ? nil
            : frontToBackWindowIDs.first { $0 != id }
        let preferredFrame = preferredFrameIfMovingAcrossMonitors(id, to: workspace, state: state)
        state.assign(id, to: workspace)
        if destinationIsVisible {
            state.activate(workspace)
        }

        do {
            try visibilityCoordinator.applyVisibleWorkspaces(
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
        let monitorSlots = windowStore.monitorSlots
        let targetSlot = state.monitorSlot(
            for: workspace,
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
        guard let frame = state.hiddenFrame(for: id) ?? windowSystem.frame(for: id) else {
            return nil
        }
        return monitorSlotResolver.translatedFrame(frame, to: targetSlot, among: monitorSlots)
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
