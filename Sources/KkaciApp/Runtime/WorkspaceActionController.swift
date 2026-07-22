import Foundation
import KkaciCore

final class WorkspaceActionController {
    private let log = Log(category: "workspace")

    private let controller: WorkspaceController
    private let previewService: SwitcherPreviewService
    private let appSettingsStore: AppSettingsStore
    private let refreshStatusSurfaces: () -> Void
    private lazy var switcherCoordinator = SwitcherCoordinator(
        controller: controller,
        previewService: previewService,
        refreshStatus: { [weak self] in
            self?.refreshStatusSurfaces()
        },
        makeOverlay: { [appSettingsStore] in
            SwitcherOverlayWindowController(appSettingsStore: appSettingsStore)
        }
    )
    init(
        controller: WorkspaceController,
        previewService: SwitcherPreviewService,
        appSettingsStore: AppSettingsStore,
        refreshStatusSurfaces: @escaping () -> Void
    ) {
        self.controller = controller
        self.previewService = previewService
        self.appSettingsStore = appSettingsStore
        self.refreshStatusSurfaces = refreshStatusSurfaces
    }

    func stepWindowSwitcher(direction: SwitcherDirection, wraps: Bool) {
        switcherCoordinator.stepWindow(direction: direction, wraps: wraps)
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

    func refreshSwitcherContent() {
        switcherCoordinator.handleContentChanged()
    }

    func switchWorkspace(to workspace: WorkspaceID) {
        cancelSwitcher()
        perform("Switched to workspace \(workspace.rawValue)") {
            try controller.switchWorkspace(to: workspace.rawValue) != nil
        }
    }

    func moveFocusedWindow(to workspace: WorkspaceID) {
        cancelSwitcher()
        do {
            guard let result = try controller.moveFocusedWindow(to: workspace.rawValue) else {
                return
            }
            guard result.outcome == .moved else {
                return
            }
            previewService.refresh(
                windowIDs: [result.windowID],
                workspaceIDs: [result.previousWorkspace, result.workspace],
                priorityIDs: [result.windowID]
            )
            switcherCoordinator.handleContentChanged()
            refreshStatusSurfaces()
            log.info("Moved \(result.windowID) to workspace \(result.workspace)")
        } catch {
            log.error("Move focused window failed: \(String(describing: error))")
        }
    }

    func centerFocusedWindow() {
        cancelSwitcher()
        do {
            let windowID = try controller.centerFocusedWindow()
            let workspaceIDs = controller.membership(for: windowID).map { Set([$0]) } ?? []
            previewService.refresh(windowIDs: [windowID], workspaceIDs: workspaceIDs)
            refreshStatusSurfaces()
            log.info("Centered window \(windowID)")
        } catch {
            log.error("Center focused window failed: \(String(describing: error))")
        }
    }

    func restoreAllHiddenWindows() {
        do {
            let result = try controller.restoreAllHiddenWindows()
            log.info(
                "Emergency restored \(result.restored.count), unavailable \(result.unavailable.count), "
                    + "failed \(result.failed.count)"
            )
        } catch {
            log.error("Emergency restore record flush failed: \(String(describing: error))")
        }
        previewService.refreshWorkspaces(ids: Set(controller.workspaces))
        refreshStatusSurfaces()
    }

    private func perform(
        _ successMessage: String,
        action: () throws -> Bool
    ) {
        do {
            guard try action() else {
                return
            }
            switcherCoordinator.handleContentChanged()
            refreshStatusSurfaces()
            log.info(successMessage)
        } catch {
            log.error("Workspace action failed: \(String(describing: error))")
        }
    }
}

extension WorkspaceActionController: KeyboardShortcutActionHandling {}
