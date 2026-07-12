import Foundation
import KkaciCore

final class WorkspaceActionController {
    private let log = Log(category: "workspace")

    private let controller: WorkspaceController
    private let thumbnailRefresher: WindowThumbnailRefresher
    private let refreshSurfaces: () -> Void
    private lazy var switcherCoordinator = SwitcherCoordinator(
        controller: controller,
        thumbnailRefresher: thumbnailRefresher,
        refreshStatus: { [weak self] in
            self?.refreshSurfaces()
        }
    )
    private var suppressedFocusedWindowID: WindowID?

    init(
        controller: WorkspaceController,
        thumbnailRefresher: WindowThumbnailRefresher,
        refreshSurfaces: @escaping () -> Void
    ) {
        self.controller = controller
        self.thumbnailRefresher = thumbnailRefresher
        self.refreshSurfaces = refreshSurfaces
    }

    func stepWindowSwitcher(direction: SwitcherDirection) {
        switcherCoordinator.stepWindow(direction: direction)
    }

    func stepWorkspaceSwitcher(direction: SwitcherDirection) {
        switcherCoordinator.stepWorkspace(direction: direction)
    }

    func commitWindowSwitcher() {
        switcherCoordinator.commitWindowSelection()
    }

    func commitWorkspaceSwitcher() {
        switcherCoordinator.commitWorkspaceSelection()
    }

    func cancelSwitcher() {
        switcherCoordinator.cancel()
    }

    func prepareSwitcher() {
        switcherCoordinator.prepareOverlay()
    }

    func switchToNextWorkspace() {
        cancelSwitcher()
        perform("Switched to next workspace") {
            _ = try controller.switchToNextWorkspace()
        }
    }

    func switchToPreviousWorkspace() {
        cancelSwitcher()
        perform("Switched to previous workspace") {
            _ = try controller.switchToPreviousWorkspace()
        }
    }

    func focusNextWindow() {
        cancelSwitcher()
        showWindowFocusResult(controller.focusNextWindow())
    }

    func focusPreviousWindow() {
        cancelSwitcher()
        showWindowFocusResult(controller.focusPreviousWindow())
    }

    func switchWorkspace(named workspace: String) {
        cancelSwitcher()
        perform("Switched to workspace \(workspace)") {
            _ = try controller.switchWorkspace(to: workspace)
        }
    }

    func moveFocusedWindow(to workspace: String) {
        cancelSwitcher()
        do {
            let result = try controller.moveFocusedWindow(to: workspace)
            if result.workspace != controller.activeWorkspace {
                suppressedFocusedWindowID = result.windowID
            }
            refreshThumbnails()
            refreshSurfaces()
            log.info("Moved \(result.windowID) to workspace \(result.workspace)")
        } catch {
            log.error("Move focused window failed: \(String(describing: error))")
        }
    }

    func createWorkspace(named workspace: String) {
        perform("Created workspace \(workspace)", shouldRefreshThumbnails: false) {
            _ = try controller.createWorkspace(named: workspace)
        }
        prepareSwitcher()
    }

    func syncWorkspaceToFocusedWindow() {
        if let suppressedFocusedWindowID,
           controller.focusedWindowID() == suppressedFocusedWindowID {
            self.suppressedFocusedWindowID = nil
            applyExternalWindowSetChange()
            return
        }

        suppressedFocusedWindowID = nil
        do {
            switch try controller.syncWorkspaceToFocusedWindow() {
            case let .switched(windowID, workspace):
                refreshThumbnails()
                refreshSurfaces()
                log.info("Switched to workspace \(workspace) for \(windowID)")
            case .alreadyActive, .noFocusedWindow, .unmanagedWindow:
                refreshThumbnails()
                refreshSurfaces()
            }
        } catch {
            log.error("Focus sync failed: \(String(describing: error))")
        }
    }

    func applyExternalWindowSetChange() {
        do {
            _ = try controller.applyExternalWindowSetChange()
            prepareSwitcher()
            refreshThumbnails()
            refreshSurfaces()
        } catch {
            log.error("Window update failed: \(String(describing: error))")
        }
    }

    func restoreAllHiddenWindows() {
        let result = controller.restoreAllHiddenWindows()
        refreshThumbnails()
        refreshSurfaces()
        log.info("Emergency restored \(result.restored.count), skipped \(result.skipped.count)")
    }

    private func perform(
        _ successMessage: String,
        shouldRefreshThumbnails: Bool = true,
        action: () throws -> Void
    ) {
        do {
            try action()
            if shouldRefreshThumbnails {
                refreshThumbnails()
            }
            refreshSurfaces()
            log.info(successMessage)
        } catch {
            log.error("Workspace action failed: \(String(describing: error))")
        }
    }

    private func showWindowFocusResult(_ result: WindowFocusResult) {
        switch result {
        case let .focused(id):
            refreshSurfaces()
            log.info("Focused \(id)")
        case let .noWindowsInWorkspace(workspace):
            log.info("No windows in workspace \(workspace)")
        }
    }

    private func refreshThumbnails() {
        thumbnailRefresher.refreshAllThumbnails()
    }
}
