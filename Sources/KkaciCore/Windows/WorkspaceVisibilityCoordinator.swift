import Foundation

final class WorkspaceVisibilityCoordinator {
    private let windowSystem: any WindowSystem
    private let hiddenWindowOperator: HiddenWindowOperator
    private let windowStore: WindowRuntimeStore

    init(
        windowSystem: any WindowSystem,
        hiddenWindowOperator: HiddenWindowOperator,
        windowStore: WindowRuntimeStore
    ) {
        self.windowSystem = windowSystem
        self.hiddenWindowOperator = hiddenWindowOperator
        self.windowStore = windowStore
    }

    func applyVisibleWorkspaces(
        state: inout WorkspaceState,
        focusWindowID: WindowID? = nil,
        hideLastWindowID: WindowID? = nil,
        requiredWindowIDs: Set<WindowID> = [],
        targetFrames: [WindowID: WindowFrame] = [:]
    ) throws {
        let currentWorkspace = state.currentWorkspace
        let visibleWorkspaces = state.visibleWorkspaces(
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
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
                    if requiredWindowIDs.contains(id) {
                        throw error
                    }
                }
            }
        }

        if let focusWindowID {
            windowSystem.focus(focusWindowID)
            windowStore.updateFocusedWindowID(focusWindowID)
        }

        for id in hideOrder(
            state: state,
            visibleWorkspaces: visibleWorkspaces,
            hideLastWindowID: hideLastWindowID
        ) {
            do {
                try hiddenWindowOperator.hide(
                    id,
                    state: &state,
                    currentWorkspace: currentWorkspace,
                    preferredFrame: targetFrames[id]
                )
            } catch {
                if requiredWindowIDs.contains(id) {
                    throw error
                }
            }
        }

        if focusWindowID == nil,
           let hideLastWindowID,
           state.isHidden(hideLastWindowID) {
            windowStore.updateFocusedWindowID(nil)
        }
    }

    func rollback(
        to previousState: WorkspaceState,
        focusedWindowID: WindowID?,
        state: inout WorkspaceState
    ) throws {
        state.restoreLogicalState(from: previousState)
        try applyVisibleWorkspaces(
            state: &state,
            focusWindowID: focusedWindowID,
            requiredWindowIDs: Set(previousState.assignedWindowIDs)
        )
        state = previousState
        windowStore.updateFocusedWindowID(focusedWindowID)
    }

    private func hideOrder(
        state: WorkspaceState,
        visibleWorkspaces: Set<String>,
        hideLastWindowID: WindowID?
    ) -> [WindowID] {
        var ids = state.assignedWindowIDs
            .filter { id in
                guard let workspace = state.membership(for: id) else {
                    return false
                }
                return !visibleWorkspaces.contains(workspace)
            }
            .sorted()

        if let hideLastWindowID, let index = ids.firstIndex(of: hideLastWindowID) {
            ids.remove(at: index)
            ids.append(hideLastWindowID)
        }

        return ids
    }
}
