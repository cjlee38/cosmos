import Foundation

final class HiddenWindowOperator {
    private let windowSystem: any WindowSystem
    private let hidePointProvider: any HidePointProviding
    private let restorableFrameResolver: RestorableFrameResolver
    private let windowCache: WindowStateCache
    private let recordRepository: HiddenWindowRecordRepository

    init(
        windowSystem: any WindowSystem,
        hidePointProvider: any HidePointProviding,
        restorableFrameResolver: RestorableFrameResolver,
        windowCache: WindowStateCache,
        recordRepository: HiddenWindowRecordRepository
    ) {
        self.windowSystem = windowSystem
        self.hidePointProvider = hidePointProvider
        self.restorableFrameResolver = restorableFrameResolver
        self.windowCache = windowCache
        self.recordRepository = recordRepository
    }

    func hide(
        _ id: WindowID,
        space: SpaceID,
        state: inout SpaceState,
        preferredFrame: WindowFrame? = nil
    ) throws {
        guard windowSystem.contains(id) else {
            throw SpaceError.windowNotFound(id)
        }
        guard let window = windowCache.snapshot(for: id) else {
            throw SpaceError.windowNotFound(id)
        }

        let currentFrame = try currentOrStoredFrame(for: id, state: state)
        let frame = preferredFrame ?? currentFrame
        let wasAlreadyHidden = state.isHidden(id)
        let hiddenSize = try prepareFrameForHiding(
            id,
            preparation: HidePreparation(
                frame: frame,
                currentFrame: currentFrame,
                preferredFrame: preferredFrame,
                wasAlreadyHidden: wasAlreadyHidden
            ),
            state: &state
        )
        let point = try hidePoint(for: frame, hiddenSize: hiddenSize)
        recordRepository.upsertRecord(
            HiddenWindowRecordPolicy.makeRecord(
                window: window,
                space: space,
                originalFrame: frame,
                hiddenPosition: point
            )
        )

        do {
            try windowSystem.setPosition(point, for: id)
            windowCache.updateFrame(
                WindowFrame(origin: point, size: hiddenSize),
                for: id
            )
        } catch {
            try rollbackFailedHide(
                id,
                rollback: HideRollback(
                    pid: window.app.pid,
                    currentFrame: currentFrame,
                    hiddenSize: hiddenSize,
                    wasAlreadyHidden: wasAlreadyHidden,
                    applyError: error
                ),
                state: &state
            )
            throw error
        }
    }

    func restore(
        _ id: WindowID,
        state: inout SpaceState,
        preferredFrame: WindowFrame? = nil
    ) throws -> RestoreResult {
        guard windowSystem.contains(id) else {
            state.clearHiddenFrame(for: id)
            recordRepository.removeAllRecords(for: id)
            throw SpaceError.windowNotFound(id)
        }

        guard let frame = state.hiddenFrame(for: id) else {
            if let preferredFrame {
                let targetFrame = try restorableFrameResolver.frameForRestore(preferredFrame)
                let appliedFrame = try windowSystem.setFrameOrMove(targetFrame, for: id)
                windowCache.updateFrame(appliedFrame, for: id)
            }
            return .alreadyVisible
        }

        let targetFrame = try restorableFrameResolver.frameForRestore(preferredFrame ?? frame)
        let appliedFrame = try windowSystem.setFrameOrMove(targetFrame, for: id)
        windowCache.updateFrame(appliedFrame, for: id)
        state.clearHiddenFrame(for: id)
        recordRepository.removeRecord(
            windowID: id,
            pid: windowCache.snapshot(for: id)?.app.pid
        )
        return .restored
    }

    func restoreForFocus(
        _ id: WindowID,
        fallbackVisibleFrame: CGRect,
        displays: [DisplaySnapshot],
        state: inout SpaceState
    ) throws {
        guard try restore(id, state: &state) == .alreadyVisible else {
            return
        }
        _ = try recoverParkingPositionForFocus(
            id,
            referenceFrame: nil,
            fallbackVisibleFrame: fallbackVisibleFrame,
            displays: displays,
            state: state
        )
    }

    func recoverParkingPositionForFocus(
        _ id: WindowID,
        referenceFrame: WindowFrame?,
        fallbackVisibleFrame: CGRect,
        displays: [DisplaySnapshot],
        state: SpaceState
    ) throws -> Bool {
        guard !state.isHidden(id),
              let frame = windowSystem.frame(for: id) ?? windowCache.snapshot(for: id)?.frame,
              hidePointProvider.isHidePosition(referenceFrame ?? frame, displays: displays)
        else {
            return false
        }
        let centeredFrame = WindowFrame(
            origin: CGPoint(
                x: fallbackVisibleFrame.midX - frame.size.width / 2,
                y: fallbackVisibleFrame.midY - frame.size.height / 2
            ),
            size: frame.size
        )
        try windowSystem.setPosition(centeredFrame.origin, for: id)
        windowCache.updateFrame(centeredFrame, for: id)
        return true
    }

    func restoreForShutdown(state: SpaceState) throws {
        var failedWindowIDs: [WindowID] = []
        for id in state.hiddenWindowIDs {
            guard let frame = state.hiddenFrame(for: id), windowSystem.contains(id) else {
                continue
            }
            do {
                let targetFrame = try restorableFrameResolver.frameForRestore(frame)
                let appliedFrame = try windowSystem.setFrameOrMove(targetFrame, for: id)
                windowCache.updateFrame(appliedFrame, for: id)
            } catch {
                failedWindowIDs.append(id)
            }
        }

        var recordFlushError: Error?
        do {
            try recordRepository.flushPendingWrites()
        } catch {
            recordFlushError = error
        }

        if failedWindowIDs.isEmpty, let recordFlushError {
            throw recordFlushError
        }
        if !failedWindowIDs.isEmpty {
            throw ShutdownRestoreError(
                failedWindowIDs: failedWindowIDs,
                recordFlushError: recordFlushError
            )
        }
    }

    private func currentOrStoredFrame(for id: WindowID, state: SpaceState) throws -> WindowFrame {
        if let hiddenFrame = state.hiddenFrame(for: id) {
            return hiddenFrame
        }
        guard let frame = windowCache.snapshot(for: id)?.frame ?? windowSystem.frame(for: id) else {
            throw SpaceError.frameUnavailable(id)
        }
        return frame
    }

    private func prepareFrameForHiding(
        _ id: WindowID,
        preparation: HidePreparation,
        state: inout SpaceState
    ) throws -> CGSize {
        let frame = preparation.frame
        let currentFrame = preparation.currentFrame
        var hiddenSize = currentFrame.size
        if preparation.preferredFrame != nil,
           !preparation.wasAlreadyHidden,
           currentFrame.size != frame.size {
            let resizeFrame = WindowFrame(origin: currentFrame.origin, size: frame.size)
            let appliedFrame = try windowSystem.setFrameOrMove(resizeFrame, for: id)
            hiddenSize = appliedFrame.size
            windowCache.updateFrame(appliedFrame, for: id)
        }
        if preparation.preferredFrame == nil {
            state.storeHiddenFrameIfNeeded(frame, for: id)
        } else {
            state.replaceHiddenFrame(frame, for: id)
        }
        return hiddenSize
    }

    private func hidePoint(for frame: WindowFrame, hiddenSize: CGSize) throws -> CGPoint {
        let displays = windowCache.displayTopology.displays
        guard let display = DisplayGeometry.display(containingOrNearest: frame.center, among: displays) else {
            throw SpaceError.noDisplayAvailable
        }
        return hidePointProvider.hidePoint(
            for: WindowFrame(origin: frame.origin, size: hiddenSize),
            on: display,
            among: displays
        )
    }

    private func rollbackFailedHide(
        _ id: WindowID,
        rollback: HideRollback,
        state: inout SpaceState
    ) throws {
        if !rollback.wasAlreadyHidden {
            recordRepository.removeRecord(windowID: id, pid: rollback.pid)
            state.clearHiddenFrame(for: id)
        }
        guard rollback.hiddenSize != rollback.currentFrame.size else {
            return
        }
        do {
            let restoredFrame = try windowSystem.setFrameOrMove(rollback.currentFrame, for: id)
            windowCache.updateFrame(restoredFrame, for: id)
        } catch let rollbackError {
            throw WindowFrameTransactionError(
                applyError: rollback.applyError,
                rollbackError: rollbackError
            )
        }
    }
}

private struct HidePreparation {
    let frame: WindowFrame
    let currentFrame: WindowFrame
    let preferredFrame: WindowFrame?
    let wasAlreadyHidden: Bool
}

private struct HideRollback {
    let pid: Int32
    let currentFrame: WindowFrame
    let hiddenSize: CGSize
    let wasAlreadyHidden: Bool
    let applyError: Error
}
