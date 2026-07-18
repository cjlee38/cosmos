import Foundation

final class WindowAssignmentCoordinator {
    private let windowCache: WindowStateCache
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator
    private let monitorSlotResolver: MonitorSlotResolver

    init(
        windowCache: WindowStateCache,
        visibilityCoordinator: WorkspaceVisibilityCoordinator,
        monitorSlotResolver: MonitorSlotResolver
    ) {
        self.windowCache = windowCache
        self.visibilityCoordinator = visibilityCoordinator
        self.monitorSlotResolver = monitorSlotResolver
    }

    func moveFocusedWindow(
        to workspace: WorkspaceID,
        frontToBackWindowIDs: [WindowID],
        state: inout WorkspaceState
    ) throws -> WindowMoveResult {
        let (id, currentWorkspace) = try focusedWindowForMove(state: state)
        guard currentWorkspace != workspace else {
            return WindowMoveResult(
                windowID: id,
                previousWorkspace: currentWorkspace.rawValue,
                workspace: workspace.rawValue,
                outcome: .alreadyInWorkspace
            )
        }

        let previousState = state
        let previousFocusedWindowID = windowCache.focusedWindowID
        let destinationIsVisible = state.visibleWorkspaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        ).contains(workspace)
        let replacementFocus = destinationIsVisible
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
                mustSucceedWindowIDs: [id],
                targetFrames: preferredFrame.map { [id: $0] } ?? [:]
            )
            return WindowMoveResult(
                windowID: id,
                previousWorkspace: currentWorkspace.rawValue,
                workspace: workspace.rawValue,
                outcome: .moved
            )
        } catch {
            try visibilityCoordinator.rollback(
                after: error,
                to: previousState,
                focusedWindowID: previousFocusedWindowID,
                state: &state
            )
            throw error
        }
    }

    private func focusedWindowForMove(state: WorkspaceState) throws -> (WindowID, WorkspaceID) {
        guard let id = windowCache.focusedWindowID else {
            throw WorkspaceError.noFocusedWindow
        }
        guard windowCache.snapshot(for: id) != nil else {
            throw WorkspaceError.windowNotFound(id)
        }
        guard let workspace = state.membership(for: id),
              workspace == state.currentWorkspace,
              !state.isHidden(id)
        else {
            throw WorkspaceError.windowNotInCurrentWorkspace(
                id,
                (state.membership(for: id) ?? state.currentWorkspace).rawValue
            )
        }
        return (id, workspace)
    }

    private func preferredFrameIfMovingAcrossMonitors(
        _ id: WindowID,
        to workspace: WorkspaceID,
        state: WorkspaceState
    ) -> WindowFrame? {
        let monitorSlots = windowCache.displayTopology.monitorSlots
        let targetSlot = state.monitorSlot(
            for: workspace,
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
        guard let frame = state.hiddenFrame(for: id) ?? windowCache.snapshot(for: id)?.frame else {
            return nil
        }
        let sourceSlot = monitorSlotResolver.slot(containing: frame, among: monitorSlots)
        guard sourceSlot != targetSlot else {
            return nil
        }
        return monitorSlotResolver.translatedFrame(frame, to: targetSlot, among: monitorSlots)
    }
}
