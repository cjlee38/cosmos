import Foundation

final class SpaceVisibilityCoordinator {
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

    func applyVisibleSpaces(
        state: inout SpaceState,
        focusWindowID: WindowID? = nil,
        hideLastWindowID: WindowID? = nil,
        mustSucceedWindowIDs: Set<WindowID> = [],
        targetFrames: [WindowID: WindowFrame] = [:]
    ) throws {
        let visibleSpaces = state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )

        for space in visibleSpaces.sorted() {
            for id in state.windowIDs(in: space) where windowCache.snapshot(for: id) != nil {
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

        for (id, space) in hideOrder(
            state: state,
            visibleSpaces: visibleSpaces,
            hideLastWindowID: hideLastWindowID
        ) where windowCache.snapshot(for: id) != nil {
            do {
                try hiddenWindowOperator.hide(
                    id,
                    space: space,
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
        to previousState: SpaceState,
        focusedWindowID: WindowID?,
        state: inout SpaceState
    ) throws {
        do {
            state.prepareForRollback(to: previousState)
            try applyVisibleSpaces(
                state: &state,
                focusWindowID: focusedWindowID,
                mustSucceedWindowIDs: Set(previousState.assignedWindowIDs)
            )
            state = previousState
            windowCache.updateFocusedWindowID(focusedWindowID)
        } catch let rollbackError {
            throw SpaceTransactionError(
                applyError: applyError,
                rollbackError: rollbackError
            )
        }
    }

    private func hideOrder(
        state: SpaceState,
        visibleSpaces: Set<SpaceID>,
        hideLastWindowID: WindowID?
    ) -> [(WindowID, SpaceID)] {
        var windows = state.assignedWindowIDs
            .compactMap { id -> (WindowID, SpaceID)? in
                guard let space = state.membership(for: id),
                      !visibleSpaces.contains(space)
                else {
                    return nil
                }
                return (id, space)
            }
            .sorted { $0.0 < $1.0 }

        if let hideLastWindowID, let index = windows.firstIndex(where: { $0.0 == hideLastWindowID }) {
            let window = windows.remove(at: index)
            windows.append(window)
        }

        return windows
    }
}
