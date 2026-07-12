import Foundation

final class WorkspaceVisibilityCoordinator {
    private let windowSystem: any WindowSystem
    private let hiddenWindowOperator: HiddenWindowOperator

    init(windowSystem: any WindowSystem, hiddenWindowOperator: HiddenWindowOperator) {
        self.windowSystem = windowSystem
        self.hiddenWindowOperator = hiddenWindowOperator
    }

    func applyActiveWorkspace(
        state: inout WorkspaceState,
        focusActiveWorkspace: Bool = false,
        preferredFocus: WindowID? = nil,
        oldFocusedWindow: WindowID? = nil,
        strictWindowIDs: Set<WindowID> = [],
        preferredFramesByWindowID: [WindowID: WindowFrame] = [:]
    ) throws {
        let activeWorkspace = state.activeWorkspace
        let visibleWorkspaces = state.activeWorkspaces.isEmpty
            ? Set([activeWorkspace])
            : state.activeWorkspaces

        for workspace in visibleWorkspaces.sorted() {
            for id in state.windowIDs(in: workspace) {
                do {
                    _ = try hiddenWindowOperator.restore(
                        id,
                        state: &state,
                        preferredFrame: preferredFramesByWindowID[id]
                    )
                } catch {
                    if strictWindowIDs.contains(id) {
                        throw error
                    }
                }
            }
        }

        if focusActiveWorkspace {
            let focusTarget = preferredFocus ?? state.focusTarget(for: activeWorkspace)
            if let focusTarget {
                windowSystem.focus(focusTarget)
                state.recordFocus(focusTarget, in: activeWorkspace)
            }
        }

        for id in hideOrder(state: state, visibleWorkspaces: visibleWorkspaces, oldFocusedWindow: oldFocusedWindow) {
            do {
                try hiddenWindowOperator.hide(
                    id,
                    state: &state,
                    activeWorkspace: activeWorkspace,
                    preferredFrame: preferredFramesByWindowID[id]
                )
            } catch {
                if strictWindowIDs.contains(id) {
                    throw error
                }
            }
        }
    }

    private func hideOrder(
        state: WorkspaceState,
        visibleWorkspaces: Set<String>,
        oldFocusedWindow: WindowID?
    ) -> [WindowID] {
        var ids = state.assignedWindowIDs
            .filter { id in
                guard let workspace = state.membership(for: id) else {
                    return false
                }
                return !visibleWorkspaces.contains(workspace)
            }
            .sorted()

        if let oldFocusedWindow, let index = ids.firstIndex(of: oldFocusedWindow) {
            ids.remove(at: index)
            ids.append(oldFocusedWindow)
        }

        return ids
    }
}
