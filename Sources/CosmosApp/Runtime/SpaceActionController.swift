import Foundation
import CosmosCore

final class SpaceActionController {
    private let log = Log(category: "space")

    private let controller: SpaceController
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
        controller: SpaceController,
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

    func stepSpaceSwitcher(direction: SwitcherDirection) {
        switcherCoordinator.stepSpace(direction: direction)
    }

    func commitWindowSwitcher() {
        switcherCoordinator.commitWindowSelection()
    }

    func commitSpaceSwitcher() {
        switcherCoordinator.commitSpaceSelection()
    }

    func cancelSwitcher() {
        switcherCoordinator.cancel()
    }

    func refreshSwitcherContent() {
        switcherCoordinator.handleContentChanged()
    }

    func switchSpace(to space: SpaceID) {
        cancelSwitcher()
        perform("Switched to space \(space.rawValue)") {
            try controller.switchSpace(to: space.rawValue) != nil
        }
    }

    func moveFocusedWindow(to space: SpaceID) {
        cancelSwitcher()
        do {
            guard let result = try controller.moveFocusedWindow(to: space.rawValue) else {
                return
            }
            guard result.outcome == .moved else {
                return
            }
            previewService.refresh(
                windowIDs: [result.windowID],
                spaceIDs: [result.previousSpace, result.space],
                priorityIDs: [result.windowID]
            )
            switcherCoordinator.handleContentChanged()
            refreshStatusSurfaces()
            log.info("Moved \(result.windowID) to space \(result.space)")
        } catch {
            log.error("Move focused window failed: \(String(describing: error))")
        }
    }

    func centerFocusedWindow() {
        cancelSwitcher()
        do {
            let windowID = try controller.centerFocusedWindow()
            let spaceIDs = controller.membership(for: windowID).map { Set([$0]) } ?? []
            previewService.refresh(windowIDs: [windowID], spaceIDs: spaceIDs)
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
        previewService.refreshSpaces(ids: Set(controller.spaces))
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
            log.error("Space action failed: \(String(describing: error))")
        }
    }
}

extension SpaceActionController: KeyboardShortcutActionHandling {}
