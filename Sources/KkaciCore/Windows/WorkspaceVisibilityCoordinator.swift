import Foundation

final class WorkspaceVisibilityCoordinator {
    private let windowSystem: any WindowSystem
    private let hiddenWindowOperator: HiddenWindowOperator
    private let windowCache: WindowStateCache

    init(
        windowSystem: any WindowSystem,
        hiddenWindowOperator: HiddenWindowOperator,
        windowCache: WindowStateCache
    ) {
        self.windowSystem = windowSystem
        self.hiddenWindowOperator = hiddenWindowOperator
        self.windowCache = windowCache
    }

    func applyVisibleWorkspaces(
        state: inout WorkspaceState,
        focusWindowID: WindowID? = nil,
        hideLastWindowID: WindowID? = nil,
        mustSucceedWindowIDs: Set<WindowID> = [],
        targetFrames: [WindowID: WindowFrame] = [:]
    ) throws {
        let visibleWorkspaces = state.visibleWorkspaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )

        for workspace in visibleWorkspaces.sorted() {
            for id in state.windowIDs(in: workspace) {
                do {
                    _ = try hiddenWindowOperator.restore(
                        id,
                        state: &state,
                        preferredFrame: targetFrames[id]
                    )
                } catch {
                    if mustSucceedWindowIDs.contains(id) {
                        throw error
                    }
                }
            }
        }

        if let focusWindowID {
            windowSystem.focus(focusWindowID)
            windowCache.updateFocusedWindowID(windowSystem.focusedWindowID())
        }

        for (id, workspace) in hideOrder(
            state: state,
            visibleWorkspaces: visibleWorkspaces,
            hideLastWindowID: hideLastWindowID
        ) {
            do {
                try hiddenWindowOperator.hide(
                    id,
                    workspace: workspace,
                    state: &state,
                    preferredFrame: targetFrames[id]
                )
            } catch {
                if mustSucceedWindowIDs.contains(id) {
                    throw error
                }
            }
        }

        if focusWindowID == nil,
           let hideLastWindowID,
           state.isHidden(hideLastWindowID) {
            windowCache.updateFocusedWindowID(nil)
        }
    }

    func rollback(
        after applyError: Error,
        to previousState: WorkspaceState,
        focusedWindowID: WindowID?,
        state: inout WorkspaceState
    ) throws {
        do {
            state.prepareForRollback(to: previousState)
            try applyVisibleWorkspaces(
                state: &state,
                focusWindowID: focusedWindowID,
                mustSucceedWindowIDs: Set(previousState.assignedWindowIDs)
            )
            state = previousState
            windowCache.updateFocusedWindowID(focusedWindowID)
        } catch let rollbackError {
            throw WorkspaceTransactionError(
                applyError: applyError,
                rollbackError: rollbackError
            )
        }
    }

    private func hideOrder(
        state: WorkspaceState,
        visibleWorkspaces: Set<WorkspaceID>,
        hideLastWindowID: WindowID?
    ) -> [(WindowID, WorkspaceID)] {
        var windows = state.assignedWindowIDs
            .compactMap { id -> (WindowID, WorkspaceID)? in
                guard let workspace = state.membership(for: id),
                      !visibleWorkspaces.contains(workspace)
                else {
                    return nil
                }
                return (id, workspace)
            }
            .sorted { $0.0 < $1.0 }

        if let hideLastWindowID, let index = windows.firstIndex(where: { $0.0 == hideLastWindowID }) {
            let window = windows.remove(at: index)
            windows.append(window)
        }

        return windows
    }
}
