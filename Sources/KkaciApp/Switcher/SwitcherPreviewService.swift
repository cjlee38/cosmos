import AppKit
import KkaciCore

struct SwitcherPreviewUpdate {
    let windowIDs: Set<WindowID>
    let workspaceIDs: Set<String>
}

final class SwitcherPreviewService {
    private let controller: WorkspaceController
    private let windowThumbnailCache: WindowThumbnailCache
    private let workspaceThumbnailCache: WorkspaceThumbnailCache
    private let applicationIconCache: ApplicationIconCache
    private var pendingUpdatedWindowIDs: Set<WindowID> = []
    private var pendingUpdatedWorkspaceIDs: Set<String> = []
    private var isUpdateNotificationScheduled = false
    private var onUpdate: ((SwitcherPreviewUpdate) -> Void)?

    init(
        controller: WorkspaceController,
        windowThumbnailCache: WindowThumbnailCache,
        workspaceThumbnailCache: WorkspaceThumbnailCache,
        applicationIconCache: ApplicationIconCache
    ) {
        self.controller = controller
        self.windowThumbnailCache = windowThumbnailCache
        self.workspaceThumbnailCache = workspaceThumbnailCache
        self.applicationIconCache = applicationIconCache

        windowThumbnailCache.setUpdateHandler { [weak self] windowID in
            self?.handleWindowThumbnailUpdated(windowID)
        }
        workspaceThumbnailCache.setUpdateHandler { [weak self] workspaceIDs in
            self?.notify(workspaceIDs: workspaceIDs)
        }
        applicationIconCache.setUpdateHandler { [weak self] pid in
            self?.handleApplicationIconUpdated(pid)
        }
    }

    func setUpdateHandler(_ handler: @escaping (SwitcherPreviewUpdate) -> Void) {
        onUpdate = handler
    }

    func windowItems(ids: [WindowID]) -> [WindowSwitcherItem] {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: controller.currentWindows().map { ($0.id, $0) }
        )
        return ids.compactMap { id in
            windowsByID[id].map(makeItem)
        }
    }

    func workspaceGroups(ids: [String]) -> [WorkspaceSwitcherGroup] {
        let liveWorkspaceIDs = Set(controller.workspaces)
        let shortcuts = WorkspaceShortcutBindings(controller.currentConfig.configuredShortcuts)
        return ids.compactMap { workspaceID in
            guard liveWorkspaceIDs.contains(workspaceID),
                  let displayFrame = displayFrame(for: workspaceID)
            else {
                return nil
            }
            return WorkspaceSwitcherGroup(
                id: workspaceID,
                displayFrame: displayFrame,
                windows: controller.windows(in: workspaceID).map(makeItem),
                preview: workspaceThumbnailCache.thumbnail(for: workspaceID),
                shortcutKey: shortcuts.key(for: workspaceID)
            )
        }
    }

    func refresh(
        windowIDs: Set<WindowID>,
        workspaceIDs: Set<String>,
        priorityIDs: [WindowID] = []
    ) {
        let windows = controller.currentWindows()
        let liveWindowIDs = Set(windows.map(\.id))
        let liveWorkspaceIDs = Set(controller.workspaces)

        windowThumbnailCache.removeStaleThumbnails(keeping: liveWindowIDs)
        workspaceThumbnailCache.removeStaleThumbnails(keeping: liveWorkspaceIDs)
        refreshApplicationIcons(windows: windows)
        let requestedWorkspaceIDs = workspaceIDs.intersection(liveWorkspaceIDs)
        let priorityWorkspaceIDs = priorityIDs.compactMap(controller.membership(for:))
        refreshWorkspaces(ids: requestedWorkspaceIDs, priorityIDs: priorityWorkspaceIDs)
        windowThumbnailCache.refresh(windowIDs: orderedWindowIDs(
            windowIDs.intersection(liveWindowIDs),
            windows: windows,
            priorityIDs: priorityIDs
        ))
    }

    func refreshWorkspaces(ids: Set<String>, priorityIDs: [String] = []) {
        let liveWorkspaceIDs = Set(controller.workspaces)
        let ids = ids.intersection(liveWorkspaceIDs)
        workspaceThumbnailCache.removeStaleThumbnails(keeping: liveWorkspaceIDs)
        workspaceThumbnailCache.refresh(
            groups: workspaceGroups(ids: controller.workspaces.filter(ids.contains)),
            priorityWorkspaceIDs: priorityIDs
        )
    }

    func refreshAll(priorityIDs: [WindowID] = []) {
        let windows = controller.currentWindows()
        refresh(
            windowIDs: Set(windows.map(\.id)),
            workspaceIDs: Set(controller.workspaces),
            priorityIDs: priorityIDs
        )
    }

    private func orderedWindowIDs(
        _ requestedWindowIDs: Set<WindowID>,
        windows: [WindowSnapshot],
        priorityIDs: [WindowID]
    ) -> [WindowID] {
        var seen: Set<WindowID> = []
        return (priorityIDs + windows.map(\.id)).filter { windowID in
            requestedWindowIDs.contains(windowID) && seen.insert(windowID).inserted
        }
    }

    private func makeItem(for window: WindowSnapshot) -> WindowSwitcherItem {
        WindowSwitcherItem(
            windowID: window.id,
            appName: window.app.name,
            title: window.title,
            frame: controller.workspaceFrame(for: window.id),
            preview: windowThumbnailCache.thumbnail(for: window.id),
            icon: applicationIconCache.icon(for: window.app.pid)
        )
    }

    private func displayFrame(for workspaceID: String) -> CGRect? {
        let monitorSlot = controller.effectiveMonitorSlot(for: workspaceID)
        return controller.displayTopology.monitorSlots
            .first { $0.slot == monitorSlot }?
            .display.frame
    }

    private func refreshApplicationIcons(windows: [WindowSnapshot]) {
        applicationIconCache.refresh(pids: Set(windows.map(\.app.pid)))
    }

    private func handleApplicationIconUpdated(_ pid: pid_t) {
        let windowIDs = Set(controller.currentWindows().filter { $0.app.pid == pid }.map(\.id))
        guard !windowIDs.isEmpty else {
            return
        }

        notify(windowIDs: windowIDs)
        refreshWorkspaces(ids: Set(windowIDs.compactMap(controller.membership(for:))))
    }

    private func handleWindowThumbnailUpdated(_ windowID: WindowID) {
        notify(windowIDs: [windowID])
        guard let workspaceID = controller.membership(for: windowID) else {
            return
        }
        refreshWorkspaces(ids: [workspaceID], priorityIDs: [workspaceID])
    }

    private func notify(
        windowIDs: Set<WindowID> = [],
        workspaceIDs: Set<String> = []
    ) {
        pendingUpdatedWindowIDs.formUnion(windowIDs)
        pendingUpdatedWorkspaceIDs.formUnion(workspaceIDs)
        guard !isUpdateNotificationScheduled else {
            return
        }

        isUpdateNotificationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            let update = SwitcherPreviewUpdate(
                windowIDs: pendingUpdatedWindowIDs,
                workspaceIDs: pendingUpdatedWorkspaceIDs
            )
            pendingUpdatedWindowIDs.removeAll()
            pendingUpdatedWorkspaceIDs.removeAll()
            isUpdateNotificationScheduled = false
            onUpdate?(update)
        }
    }
}
