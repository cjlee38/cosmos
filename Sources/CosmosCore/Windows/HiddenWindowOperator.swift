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

        let frame = try preferredFrame ?? currentOrStoredFrame(for: id, state: state)
        let wasAlreadyHidden = state.isHidden(id)
        if preferredFrame == nil {
            state.storeHiddenFrameIfNeeded(frame, for: id)
        } else {
            state.replaceHiddenFrame(frame, for: id)
        }

        let point = try hidePointProvider.hidePoint(for: frame)
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
                WindowFrame(origin: point, size: frame.size),
                for: id
            )
        } catch {
            if !wasAlreadyHidden {
                recordRepository.removeRecord(
                    windowID: id,
                    pid: window.app.pid
                )
                state.clearHiddenFrame(for: id)
            }
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
}
