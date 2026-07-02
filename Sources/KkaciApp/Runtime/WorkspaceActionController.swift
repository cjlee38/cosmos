import Foundation
import KkaciCore

final class WorkspaceActionController {
    private let controller: WorkspaceController
    private let eventLog: RuntimeEventLog
    private let refreshSurfaces: () -> Void
    private lazy var switcherCoordinator = SwitcherCoordinator(
        controller: controller,
        eventLog: eventLog,
        refreshStatus: { [weak self] in
            self?.refreshSurfaces()
        }
    )
    private var suppressedFocusedWindowID: WindowID?

    init(
        controller: WorkspaceController,
        eventLog: RuntimeEventLog,
        refreshSurfaces: @escaping () -> Void
    ) {
        self.controller = controller
        self.eventLog = eventLog
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
            eventLog.record("Moved \(result.windowID) to workspace \(result.workspace)")
        } catch {
            eventLog.record("Error: \(error)")
        }
    }

    func createWorkspace(named workspace: String) {
        perform("Created workspace \(workspace)") {
            _ = try controller.createWorkspace(named: workspace)
        }
    }

    func syncWorkspaceToFocusedWindow() {
        if let suppressedFocusedWindowID,
           controller.focusedWindowID() == suppressedFocusedWindowID
        {
            self.suppressedFocusedWindowID = nil
            applyExternalWindowSetChange()
            return
        }

        suppressedFocusedWindowID = nil
        do {
            switch try controller.syncWorkspaceToFocusedWindow() {
            case .switched(let windowID, let workspace):
                eventLog.record("Switched to workspace \(workspace) for \(windowID)")
            case .alreadyActive(_, _), .noFocusedWindow, .unmanagedWindow(_):
                refreshSurfaces()
            }
        } catch {
            eventLog.record("Focus sync failed: \(error)")
        }
    }

    func applyExternalWindowSetChange() {
        do {
            _ = try controller.applyExternalWindowSetChange()
            refreshSurfaces()
        } catch {
            eventLog.record("Window update failed: \(error)")
        }
    }

    func restoreAllHiddenWindows() {
        let result = controller.restoreAllHiddenWindows()
        eventLog.record("Emergency restored \(result.restored.count), skipped \(result.skipped.count)")
    }

    private func perform(_ successMessage: String, action: () throws -> Void) {
        do {
            try action()
            eventLog.record(successMessage)
        } catch {
            eventLog.record("Error: \(error)")
        }
    }

    private func showWindowFocusResult(_ result: WindowFocusResult) {
        switch result {
        case .focused(let id):
            eventLog.record("Focused \(id)")
        case .noWindowsInWorkspace(let workspace):
            eventLog.record("No windows in workspace \(workspace)")
        }
    }
}
