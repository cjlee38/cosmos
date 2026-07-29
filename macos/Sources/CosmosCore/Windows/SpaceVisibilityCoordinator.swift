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
        excludedWindowIDs: Set<WindowID> = [],
        targetFrames: [WindowID: WindowFrame] = [:]
    ) throws {
        let visibleSpaces = state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )

        for space in visibleSpaces.sorted() {
            for id in state.windowIDs(in: space)
                where windowCache.snapshot(for: id) != nil
                && !excludedWindowIDs.contains(id) {
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
        ) where windowCache.snapshot(for: id) != nil
            && !excludedWindowIDs.contains(id) {
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

    func applyContinuityRecovery(
        windowIDs: Set<WindowID>,
        targetFrames: [WindowID: WindowFrame],
        state: inout SpaceState
    ) -> WindowContinuityApplyResult {
        let visibleSpaces = state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
        var succeeded: Set<WindowID> = []
        var failed: Set<WindowID> = []

        for id in windowIDs.sorted() {
            guard let space = state.membership(for: id),
                  windowCache.snapshot(for: id) != nil,
                  let targetFrame = targetFrames[id]
            else {
                failed.insert(id)
                continue
            }
            do {
                if visibleSpaces.contains(space) {
                    _ = try hiddenWindowOperator.restore(
                        id,
                        state: &state,
                        preferredFrame: targetFrame
                    )
                } else {
                    try hiddenWindowOperator.hide(
                        id,
                        space: space,
                        state: &state,
                        preferredFrame: targetFrame
                    )
                }
                succeeded.insert(id)
            } catch {
                failed.insert(id)
            }
        }
        return WindowContinuityApplyResult(
            succeededWindowIDs: succeeded,
            failedWindowIDs: failed
        )
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

struct WindowContinuityApplyResult {
    let succeededWindowIDs: Set<WindowID>
    let failedWindowIDs: Set<WindowID>
}
