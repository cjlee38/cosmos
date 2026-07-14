import Foundation

final class HiddenWindowOperator {
    private let windowSystem: any WindowSystem
    private let displayProvider: any HidePointProviding
    private let restorableFrameResolver: RestorableFrameResolver
    private let windowStore: WindowRuntimeStore
    private let recordRepository: HiddenWindowRecordRepository

    init(
        windowSystem: any WindowSystem,
        displayProvider: any HidePointProviding,
        restorableFrameResolver: RestorableFrameResolver,
        windowStore: WindowRuntimeStore,
        recordRepository: HiddenWindowRecordRepository
    ) {
        self.windowSystem = windowSystem
        self.displayProvider = displayProvider
        self.restorableFrameResolver = restorableFrameResolver
        self.windowStore = windowStore
        self.recordRepository = recordRepository
    }

    func hide(
        _ id: WindowID,
        state: inout WorkspaceState,
        activeWorkspace: String,
        preferredFrame: WindowFrame? = nil
    ) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }
        guard let window = windowStore.snapshot(for: id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let frame = try preferredFrame ?? currentOrStoredFrame(for: id, state: state)
        let wasAlreadyHidden = state.isHidden(id)
        if preferredFrame == nil {
            state.storeHiddenFrameIfNeeded(frame, for: id)
        } else {
            state.replaceHiddenFrame(frame, for: id)
        }

        let point = displayProvider.hidePoint(for: frame)
        recordRepository.upsertRecord(
            HiddenWindowRecordPolicy.makeRecord(
                window: window,
                workspace: state.membership(for: id) ?? activeWorkspace,
                originalFrame: frame,
                hiddenPosition: point
            )
        )

        do {
            try windowSystem.setPosition(point, for: id)
            windowStore.updateFrame(
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
        state: inout WorkspaceState,
        preferredFrame: WindowFrame? = nil
    ) throws -> RestoreResult {
        guard windowSystem.contains(id) else {
            state.clearHiddenFrame(for: id)
            recordRepository.removeAllRecords(for: id)
            throw WorkspaceError.windowNotFound(id)
        }

        guard let frame = state.hiddenFrame(for: id) else {
            if let preferredFrame {
                let targetFrame = restorableFrameResolver.frameForRestore(preferredFrame)
                try windowSystem.setFrameIfSizeChanged(targetFrame, for: id)
                windowStore.updateFrame(targetFrame, for: id)
            }
            return .alreadyVisible
        }

        let targetFrame = restorableFrameResolver.frameForRestore(preferredFrame ?? frame)
        try windowSystem.setFrameIfSizeChanged(targetFrame, for: id)
        windowStore.updateFrame(targetFrame, for: id)
        state.clearHiddenFrame(for: id)
        recordRepository.removeRecord(
            windowID: id,
            pid: windowStore.snapshot(for: id)?.app.pid
        )
        return .restored
    }

    func restoreForShutdown(state: WorkspaceState) throws {
        var failedWindowIDs: [WindowID] = []
        for id in state.hiddenWindowIDs {
            guard let frame = state.hiddenFrame(for: id), windowSystem.contains(id) else {
                continue
            }
            let targetFrame = restorableFrameResolver.frameForRestore(frame)
            do {
                try windowSystem.setFrameIfSizeChanged(targetFrame, for: id)
                windowStore.updateFrame(targetFrame, for: id)
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

    private func currentOrStoredFrame(for id: WindowID, state: WorkspaceState) throws -> WindowFrame {
        if let hiddenFrame = state.hiddenFrame(for: id) {
            return hiddenFrame
        }
        guard let frame = windowSystem.frame(for: id) else {
            throw WorkspaceError.frameUnavailable(id)
        }
        return frame
    }
}
