import Foundation
import KkaciCore

final class WindowRuntimeEventHandler {
    private let log = Log(category: "window-events")

    private let controller: WorkspaceController
    private let previewService: SwitcherPreviewService
    private let refreshSwitcherContent: () -> Void
    private let refreshSurfaces: () -> Void
    private var focusSyncSuppression = FocusSyncSuppression()

    init(
        controller: WorkspaceController,
        previewService: SwitcherPreviewService,
        refreshSwitcherContent: @escaping () -> Void,
        refreshSurfaces: @escaping () -> Void
    ) {
        self.controller = controller
        self.previewService = previewService
        self.refreshSwitcherContent = refreshSwitcherContent
        self.refreshSurfaces = refreshSurfaces
    }

    func suppressNextFocusSync(for windowID: WindowID) {
        focusSyncSuppression.suppress(windowID)
    }

    func handle(_ events: WindowRuntimeEventBatch) {
        let previousMemberships = currentMemberships()
        let focusedWindowID = controller.focusedWindowID()
        let shouldFollowFocusedWindow = focusSyncSuppression.shouldFollow(
            requested: shouldFollowFocusedWindow(for: events, focusedWindowID: focusedWindowID),
            focusedWindowID: focusedWindowID
        )

        do {
            let result = try shouldFollowFocusedWindow
                ? controller.handleFocusedWindowChanged()
                : controller.handleWindowSetChanged()
            refreshPreviews(
                for: events,
                result: result,
                previousMemberships: previousMemberships
            )
            refreshSwitcherContent()
            refreshSurfaces()
            if case let .switched(windowID, workspace) = result.focusedWindowSync {
                log.info("Switched to workspace \(workspace) for \(windowID)")
            }
        } catch {
            log.error("Window update failed: \(String(describing: error))")
        }
    }

    private func refreshPreviews(
        for events: WindowRuntimeEventBatch,
        result: ExternalWindowEventResult,
        previousMemberships: [WindowID: String]
    ) {
        let windows = controller.currentWindows()
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

        previewService.refresh(
            windowIDs: windowIDs,
            workspaceNames: workspaceNames,
            priorityIDs: controller.focusedWindowID().map { [$0] } ?? []
        )
    }

    private func currentMemberships() -> [WindowID: String] {
        Dictionary(uniqueKeysWithValues: controller.currentWindows().compactMap { window in
            controller.membership(for: window.id).map { (window.id, $0) }
        })
    }

    private func shouldFollowFocusedWindow(
        for events: WindowRuntimeEventBatch,
        focusedWindowID: WindowID?
    ) -> Bool {
        if events.shouldFollowFocusedWindow {
            return true
        }
        guard events.containsLayoutChange, let focusedWindowID else {
            return false
        }
        return !controller.isHiddenByWorkspace(focusedWindowID)
    }
}

struct FocusSyncSuppression {
    private var windowID: WindowID?

    mutating func suppress(_ windowID: WindowID) {
        self.windowID = windowID
    }

    mutating func shouldFollow(requested: Bool, focusedWindowID: WindowID?) -> Bool {
        guard requested else {
            return false
        }
        guard let windowID else {
            return true
        }

        self.windowID = nil
        return focusedWindowID != windowID
    }
}
