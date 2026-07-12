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
            let previousWorkspace = controller.focusedWindowID().flatMap(controller.membership(for:))
            let result = try controller.moveFocusedWindow(to: workspace)
            if result.workspace != controller.activeWorkspace {
                suppressedFocusedWindowID = result.windowID
            }
            thumbnailRefresher.refreshThumbnails(
                windowIDs: [result.windowID],
                workspaceNames: Set([previousWorkspace, result.workspace].compactMap { $0 }),
                priorityIDs: [result.windowID]
            )
            refreshSurfaces()
            log.info("Moved \(result.windowID) to workspace \(result.workspace)")
        } catch {
            log.error("Move focused window failed: \(String(describing: error))")
        }
    }

    func createWorkspace(named workspace: String) {
        perform("Created workspace \(workspace)") {
            _ = try controller.createWorkspace(named: workspace)
        }
        thumbnailRefresher.refreshWorkspaceThumbnails(names: [workspace])
        prepareSwitcher()
    }

    func applyExternalWindowEvents(_ events: WindowRuntimeEventBatch) {
        let previousMemberships = currentMemberships()
        var shouldFollowFocusedWindow = events.shouldFollowFocusedWindow
        if let suppressedFocusedWindowID,
           controller.focusedWindowID() == suppressedFocusedWindowID {
            self.suppressedFocusedWindowID = nil
            shouldFollowFocusedWindow = false
        } else {
            suppressedFocusedWindowID = nil
        }

        do {
            let result = try controller.applyExternalWindowEvents(
                followFocusedWindow: shouldFollowFocusedWindow
            )
            let windows = controller.currentWindows().windows
            let liveWindowIDs = Set(windows.map(\.id))
            let autoAssignedWindowIDs = Set(result.sync.autoAssigned.map(\.0))
            var affectedWindowIDs = events.windowIDs
                .union(autoAssignedWindowIDs)
                .union(result.sync.removed)
            if events.shouldFollowFocusedWindow, let focusedWindowID = controller.focusedWindowID() {
                affectedWindowIDs.insert(focusedWindowID)
            }

            let windowIDs: Set<WindowID>
            let workspaceNames: Set<String>
            if events.needsFullThumbnailRefresh {
                windowIDs = liveWindowIDs
                workspaceNames = Set(controller.workspaces)
            } else {
                windowIDs = events.windowIDsNeedingCapture
                    .union(autoAssignedWindowIDs)
                    .intersection(liveWindowIDs)
                workspaceNames = Set(affectedWindowIDs.compactMap { windowID in
                    previousMemberships[windowID]
                }).union(affectedWindowIDs.compactMap(controller.membership(for:)))
            }

            thumbnailRefresher.refreshThumbnails(
                windowIDs: windowIDs,
                workspaceNames: workspaceNames,
                priorityIDs: controller.focusedWindowID().map { [$0] } ?? []
            )
            if !result.sync.autoAssigned.isEmpty || !result.sync.removed.isEmpty {
                prepareSwitcher()
            }
            refreshSurfaces()
            if case let .switched(windowID, workspace) = result.focusedWindowSync {
                log.info("Switched to workspace \(workspace) for \(windowID)")
            }
        } catch {
            log.error("Window update failed: \(String(describing: error))")
        }
    }

    func restoreAllHiddenWindows() {
        let result = controller.restoreAllHiddenWindows()
        thumbnailRefresher.refreshWorkspaceThumbnails(names: Set(controller.workspaces))
        refreshSurfaces()
        log.info("Emergency restored \(result.restored.count), skipped \(result.skipped.count)")
    }

    private func perform(
        _ successMessage: String,
        action: () throws -> Void
    ) {
        do {
            try action()
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

    private func currentMemberships() -> [WindowID: String] {
        Dictionary(uniqueKeysWithValues: controller.currentWindows().windows.compactMap { window in
            controller.membership(for: window.id).map { (window.id, $0) }
        })
    }
}
