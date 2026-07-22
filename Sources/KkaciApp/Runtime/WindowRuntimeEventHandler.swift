import Foundation
import KkaciCore

final class WindowRuntimeEventHandler {
    private let log = Log(category: "window-events")

    private let controller: WorkspaceController
    private let previewService: SwitcherPreviewService
    private let refreshSwitcherContent: () -> Void
    private let refreshStatusSurfaces: () -> Void

    init(
        controller: WorkspaceController,
        previewService: SwitcherPreviewService,
        refreshSwitcherContent: @escaping () -> Void,
        refreshStatusSurfaces: @escaping () -> Void
    ) {
        self.controller = controller
        self.previewService = previewService
        self.refreshSwitcherContent = refreshSwitcherContent
        self.refreshStatusSurfaces = refreshStatusSurfaces
    }

    func handleOwnWindowVisibilityChanged() {
        do {
            _ = try controller.handleOwnWindowVisibilityChanged()
            refreshSwitcherContent()
            refreshStatusSurfaces()
        } catch {
            log.error("Own-window visibility update failed: \(String(describing: error))")
        }
    }

    func handle(_ events: WindowRuntimeEventBatch) {
        do {
            let focusPolicy: ExternalWindowFocusPolicy = if events.containsApplicationActivation {
                .always
            } else if events.containsFocusChange || events.containsLayoutChange {
                .visibleFocusedWindow
            } else {
                .never
            }
            let result = try controller.handleExternalWindowChange(ExternalWindowChange(
                displayConfigurationChanged: events.containsDisplayChange,
                focusPolicy: focusPolicy
            ))
            refreshPreviews(for: events, result: result)
            refreshSwitcherContent()
            refreshStatusSurfaces()
            if case let .switched(windowID, workspace) = result.focusedWindowSync {
                log.info("Switched to workspace \(workspace) for \(windowID)")
            }
        } catch {
            log.error("Window update failed: \(String(describing: error))")
        }
    }

    private func refreshPreviews(
        for events: WindowRuntimeEventBatch,
        result: ExternalWindowEventResult
    ) {
        let windows = controller.currentWindows()
        let liveWindowIDs = Set(windows.map(\.id))
        let autoAssignedWindowIDs = Set(result.sync.autoAssigned.map(\.0))
        var affectedWindowIDs = events.windowIDs
            .union(result.sync.affectedWindowIDs)
        let focusedWindowID = controller.cachedFocusedWindowID()
        if events.containsFocusChange, let focusedWindowID {
            affectedWindowIDs.insert(focusedWindowID)
        }

        let windowIDs: Set<WindowID>
        let workspaceIDs: Set<String>
        if events.needsFullThumbnailRefresh {
            windowIDs = liveWindowIDs
            workspaceIDs = Set(controller.workspaces)
        } else {
            windowIDs = events.windowIDsNeedingCapture
                .union(autoAssignedWindowIDs)
                .intersection(liveWindowIDs)
            workspaceIDs = result.sync.affectedWorkspaces
                .union(affectedWindowIDs.compactMap(controller.membership(for:)))
        }

        previewService.refresh(
            windowIDs: windowIDs,
            workspaceIDs: workspaceIDs,
            priorityIDs: focusedWindowID.map { [$0] } ?? []
        )
    }
}
