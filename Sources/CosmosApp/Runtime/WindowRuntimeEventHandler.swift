import Foundation
import CosmosCore

final class WindowRuntimeEventHandler {
    private let log = Log(category: "window-events")

    private let controller: SpaceController
    private let previewService: SwitcherPreviewService
    private let refreshSwitcherContent: () -> Void
    private let refreshStatusSurfaces: () -> Void

    init(
        controller: SpaceController,
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
            if case let .switched(windowID, space) = result.focusedWindowSync {
                log.info("Switched to space \(space) for \(windowID)")
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
        let spaceIDs: Set<String>
        if events.needsFullThumbnailRefresh {
            windowIDs = liveWindowIDs
            spaceIDs = Set(controller.spaces)
        } else {
            windowIDs = events.windowIDsNeedingCapture
                .union(autoAssignedWindowIDs)
                .intersection(liveWindowIDs)
            spaceIDs = result.sync.affectedSpaces
                .union(affectedWindowIDs.compactMap(controller.membership(for:)))
        }

        previewService.refresh(
            windowIDs: windowIDs,
            spaceIDs: spaceIDs,
            priorityIDs: focusedWindowID.map { [$0] } ?? []
        )
    }
}
