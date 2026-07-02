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
        strictWindowIDs: Set<WindowID> = []
    ) throws {
        let activeWorkspace = state.activeWorkspace
        var firstRestored: WindowID?

        for id in state.windowIDs(in: activeWorkspace) {
            do {
                _ = try hiddenWindowOperator.restore(id, state: &state)
            } catch {
                if strictWindowIDs.contains(id) {
                    throw error
                }
            }
            firstRestored = firstRestored ?? id
        }

        if focusActiveWorkspace {
            let focusTarget = preferredFocus ?? state.focusTarget(for: activeWorkspace, fallback: firstRestored)
            if let focusTarget {
                windowSystem.focus(focusTarget)
                state.recordFocus(focusTarget, in: activeWorkspace)
            }
        }

        for id in hideOrder(state: state, targetWorkspace: activeWorkspace, oldFocusedWindow: oldFocusedWindow) {
            do {
                try hiddenWindowOperator.hide(id, state: &state, activeWorkspace: activeWorkspace)
            } catch {
                if strictWindowIDs.contains(id) {
                    throw error
                }
            }
        }
    }

    private func hideOrder(
        state: WorkspaceState,
        targetWorkspace: String,
        oldFocusedWindow: WindowID?
    ) -> [WindowID] {
        var ids = state.assignedWindowIDs
            .filter { state.membership(for: $0) != targetWorkspace }
            .sorted()

        if let oldFocusedWindow, let index = ids.firstIndex(of: oldFocusedWindow) {
            ids.remove(at: index)
            ids.append(oldFocusedWindow)
        }

        return ids
    }
}
