import Foundation

final class HiddenWindowOperator {
    private let windowSystem: any WindowSystem
    private let hidePointProvider: any HidePointProviding
    private let restorableFrameResolver: RestorableFrameResolver
    private let windowCache: WindowStateCache
    private let recordRepository: HiddenWindowRecordRepository
    private let frameApplicationEvaluator: WindowFrameApplicationEvaluator

    init(
        windowSystem: any WindowSystem,
        hidePointProvider: any HidePointProviding,
        restorableFrameResolver: RestorableFrameResolver,
        windowCache: WindowStateCache,
        recordRepository: HiddenWindowRecordRepository,
        frameApplicationEvaluator: WindowFrameApplicationEvaluator
    ) {
        self.windowSystem = windowSystem
        self.hidePointProvider = hidePointProvider
        self.restorableFrameResolver = restorableFrameResolver
        self.windowCache = windowCache
        self.recordRepository = recordRepository
        self.frameApplicationEvaluator = frameApplicationEvaluator
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
        let previousHiddenFrame = state.hiddenFrame(for: id)
        let previousRecord = try recordRepository.record(
            windowID: id,
            pid: window.app.pid
        )
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
        let record = HiddenWindowRecordPolicy.makeRecord(
            window: window,
            space: space,
            originalFrame: frame,
            hiddenPosition: point
        )
        recordRepository.upsertRecord(record)

        var didApplyPosition = false
        do {
            try applyHidePosition(
                point,
                hiddenSize: hiddenSize,
                windowID: id,
                record: record,
                didApplyPosition: &didApplyPosition
            )
        } catch {
            try rollbackFailedHide(
                id,
                rollback: HideRollback(
                    pid: window.app.pid,
                    currentFrame: currentFrame,
                    hiddenSize: hiddenSize,
                    previousHiddenFrame: previousHiddenFrame,
                    previousRecord: previousRecord,
                    newRecord: record,
                    applyError: error,
                    didApplyPosition: didApplyPosition
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
                let appliedFrame = try applyVisibleFrame(
                    targetFrame,
                    operation: "restore-visible",
                    windowID: id
                )
                windowCache.updateFrame(appliedFrame, for: id)
            }
            return .alreadyVisible
        }

        let targetFrame = try restorableFrameResolver.frameForRestore(preferredFrame ?? frame)
        let appliedFrame = try applyVisibleFrame(
            targetFrame,
            operation: "restore-hidden",
            windowID: id
        )
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
        let appliedFrame = try applyVisiblePosition(
            centeredFrame,
            operation: "recover-parking-focus",
            windowID: id
        )
        windowCache.updateFrame(appliedFrame, for: id)
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
                let appliedFrame = try applyVisibleFrame(
                    targetFrame,
                    operation: "restore-shutdown",
                    windowID: id
                )
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
            let observation = try windowSystem.setFrameOrMove(resizeFrame, for: id)
            let appliedFrame = frameApplicationEvaluator.observedFrame(
                observation,
                targetFrame: resizeFrame
            )
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
        guard rollback.didApplyPosition || rollback.hiddenSize != rollback.currentFrame.size else {
            restorePreviousHideState(id, rollback: rollback, state: &state)
            return
        }
        do {
            let restoredFrame = try applyVisibleFrame(
                rollback.currentFrame,
                operation: "hide-rollback",
                windowID: id
            )
            windowCache.updateFrame(restoredFrame, for: id)
        } catch let rollbackError {
            preserveFailedHideRecovery(id, record: rollback.newRecord)
            throw WindowFrameTransactionError(
                applyError: rollback.applyError,
                rollbackError: rollbackError
            )
        }
        restorePreviousHideState(id, rollback: rollback, state: &state)
    }

    private func restorePreviousHideState(
        _ id: WindowID,
        rollback: HideRollback,
        state: inout SpaceState
    ) {
        if let previousHiddenFrame = rollback.previousHiddenFrame {
            state.replaceHiddenFrame(previousHiddenFrame, for: id)
            if let previousRecord = rollback.previousRecord {
                recordRepository.upsertRecord(previousRecord)
            } else {
                recordRepository.removeRecord(windowID: id, pid: rollback.pid)
            }
        } else {
            recordRepository.removeRecord(windowID: id, pid: rollback.pid)
            state.clearHiddenFrame(for: id)
        }
    }

    private func preserveFailedHideRecovery(
        _ id: WindowID,
        record: HiddenWindowRecord
    ) {
        guard let actualFrame = windowSystem.frame(for: id) else {
            recordRepository.upsertRecord(record)
            return
        }
        windowCache.updateFrame(actualFrame, for: id)
        updateHiddenRecordIfNeeded(record, appliedFrame: actualFrame)
    }
}

private extension HiddenWindowOperator {
    func applyHidePosition(
        _ point: CGPoint,
        hiddenSize: CGSize,
        windowID: WindowID,
        record: HiddenWindowRecord,
        didApplyPosition: inout Bool
    ) throws {
        let targetFrame = WindowFrame(origin: point, size: hiddenSize)
        let observation = try windowSystem.setPositionAndObserve(point, for: windowID)
        didApplyPosition = true
        let appliedFrame = try frameApplicationEvaluator.parkedFrame(
            observation,
            operation: "hide",
            windowID: windowID,
            targetFrame: targetFrame
        )
        updateHiddenRecordIfNeeded(record, appliedFrame: appliedFrame)
        windowCache.updateFrame(appliedFrame, for: windowID)
    }

    func applyVisibleFrame(
        _ targetFrame: WindowFrame,
        operation: String,
        windowID: WindowID
    ) throws -> WindowFrame {
        let observation = try windowSystem.setFrameOrMove(targetFrame, for: windowID)
        return try frameApplicationEvaluator.visibleFrame(
            observation,
            operation: operation,
            windowID: windowID,
            targetFrame: targetFrame
        )
    }

    func applyVisiblePosition(
        _ targetFrame: WindowFrame,
        operation: String,
        windowID: WindowID
    ) throws -> WindowFrame {
        let observation = try windowSystem.setPositionAndObserve(targetFrame.origin, for: windowID)
        return try frameApplicationEvaluator.visibleFrame(
            observation,
            operation: operation,
            windowID: windowID,
            targetFrame: targetFrame
        )
    }

    func updateHiddenRecordIfNeeded(
        _ record: HiddenWindowRecord,
        appliedFrame: WindowFrame
    ) {
        guard appliedFrame.origin != record.hiddenPosition else {
            return
        }
        recordRepository.upsertRecord(HiddenWindowRecord(
            windowID: record.windowID,
            pid: record.pid,
            space: record.space,
            originalFrame: record.originalFrame,
            hiddenPosition: appliedFrame.origin
        ))
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
    let previousHiddenFrame: WindowFrame?
    let previousRecord: HiddenWindowRecord?
    let newRecord: HiddenWindowRecord
    let applyError: Error
    let didApplyPosition: Bool
}
