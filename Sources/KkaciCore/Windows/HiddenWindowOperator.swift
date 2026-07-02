import Foundation

final class HiddenWindowOperator {
    private let windowSystem: any WindowSystem
    private let displayProvider: any HidePointProviding
    private let windowStore: WindowRuntimeStore

    init(
        windowSystem: any WindowSystem,
        displayProvider: any HidePointProviding,
        windowStore: WindowRuntimeStore
    ) {
        self.windowSystem = windowSystem
        self.displayProvider = displayProvider
        self.windowStore = windowStore
    }

    func hide(_ id: WindowID, state: inout WorkspaceState, activeWorkspace: String) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let frame = try currentOrStoredFrame(for: id, state: state)
        let wasAlreadyHidden = state.isHidden(id)
        state.storeHiddenFrameIfNeeded(frame, for: id)

        let point = displayProvider.hidePoint(for: frame)
        windowStore.saveHiddenRecord(
            windowID: id,
            workspace: state.membership(for: id) ?? activeWorkspace,
            originalFrame: frame,
            hiddenPosition: point
        )

        do {
            try windowSystem.setPosition(point, for: id)
        } catch {
            if !wasAlreadyHidden {
                windowStore.removeHiddenRecord(for: id)
                state.clearHiddenFrame(for: id)
            }
            throw error
        }
    }

    func restore(_ id: WindowID, state: inout WorkspaceState) throws -> RestoreResult {
        guard windowSystem.contains(id) else {
            state.clearHiddenFrame(for: id)
            windowStore.removeAllHiddenRecords(for: id)
            throw WorkspaceError.windowNotFound(id)
        }

        guard let frame = state.hiddenFrame(for: id) else {
            return .alreadyVisible
        }

        try windowSystem.setPosition(frame.origin, for: id)
        state.clearHiddenFrame(for: id)
        windowStore.removeHiddenRecord(for: id)
        return .restored
    }

    func restoreForShutdown(state: WorkspaceState) {
        for id in state.hiddenWindowIDs {
            guard let frame = state.hiddenFrame(for: id), windowSystem.contains(id) else {
                continue
            }
            try? windowSystem.setPosition(frame.origin, for: id)
        }
        windowStore.flushHiddenRecordWrites()
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
