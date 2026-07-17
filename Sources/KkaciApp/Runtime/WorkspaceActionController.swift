import Foundation
import KkaciCore

final class WorkspaceActionController {
    private let log = Log(category: "workspace")

    private let controller: WorkspaceController
    private let previewService: SwitcherPreviewService
    private let appSettingsStore: AppSettingsStore
    private let refreshSurfaces: () -> Void
    private let suppressNextFocusSync: (WindowID) -> Void
    private lazy var switcherCoordinator = SwitcherCoordinator(
        controller: controller,
        previewService: previewService,
        refreshStatus: { [weak self] in
            self?.refreshSurfaces()
        },
        makeOverlay: { [appSettingsStore] in
            SwitcherOverlayWindowController(appSettingsStore: appSettingsStore)
        }
    )
    init(
        controller: WorkspaceController,
        previewService: SwitcherPreviewService,
        appSettingsStore: AppSettingsStore,
        refreshSurfaces: @escaping () -> Void,
        suppressNextFocusSync: @escaping (WindowID) -> Void
    ) {
        self.controller = controller
        self.previewService = previewService
        self.appSettingsStore = appSettingsStore
        self.refreshSurfaces = refreshSurfaces
        self.suppressNextFocusSync = suppressNextFocusSync
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

    func switchWorkspace(named workspace: String) {
        cancelSwitcher()
        perform("Switched to workspace \(workspace)") {
            try controller.switchWorkspace(to: workspace) != nil
        }
    }

    func moveFocusedWindow(to workspace: String) {
        cancelSwitcher()
        do {
            let previousWorkspace = controller.focusedWindowID().flatMap(controller.membership(for:))
            guard let result = try controller.moveFocusedWindow(to: workspace) else {
                return
            }
            if result.workspace != controller.currentWorkspace {
                suppressNextFocusSync(result.windowID)
            }
            previewService.refresh(
                windowIDs: [result.windowID],
                workspaceNames: Set([previousWorkspace, result.workspace].compactMap { $0 }),
                priorityIDs: [result.windowID]
            )
            switcherCoordinator.handleContentChanged()
            refreshSurfaces()
            log.info("Moved \(result.windowID) to workspace \(result.workspace)")
        } catch {
            log.error("Move focused window failed: \(String(describing: error))")
        }
    }

    func restoreAllHiddenWindows() {
        do {
            let result = try controller.restoreAllHiddenWindows()
            log.info("Emergency restored \(result.restored.count), skipped \(result.skipped.count)")
        } catch {
            log.error("Emergency restore record flush failed: \(String(describing: error))")
        }
        previewService.refreshWorkspaces(names: Set(controller.workspaces))
        refreshSurfaces()
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
            refreshSurfaces()
            log.info(successMessage)
        } catch {
            log.error("Workspace action failed: \(String(describing: error))")
        }
    }
}

extension WorkspaceActionController: KeyboardShortcutActionHandling {}
