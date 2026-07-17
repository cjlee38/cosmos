import AppKit
import KkaciCore

struct SwitcherPreviewUpdate {
    let windowIDs: Set<WindowID>
    let workspaceNames: Set<String>
}

final class SwitcherPreviewService {
    private let controller: WorkspaceController
    private let windowThumbnailCache: WindowThumbnailCache
    private let workspaceThumbnailCache: WorkspaceThumbnailCache
    private let applicationIconCache: ApplicationIconCache
    private var pendingWorkspaceNames: Set<String> = []
    private var pendingUpdatedWindowIDs: Set<WindowID> = []
    private var pendingUpdatedWorkspaceNames: Set<String> = []
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

        windowThumbnailCache.setUpdateHandlers(
            onThumbnailUpdated: { [weak self] windowID in
                self?.notify(windowIDs: [windowID])
            },
            onCaptureCycleCompleted: { [weak self] in
                self?.flushPendingWorkspaceThumbnails()
            }
        )
        workspaceThumbnailCache.setUpdateHandler { [weak self] workspaceNames in
            self?.notify(workspaceNames: workspaceNames)
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
        let shortcuts = WorkspaceShortcutBindings(controller.currentConfig.bindings)
        return ids.compactMap { workspaceID in
            guard liveWorkspaceIDs.contains(workspaceID) else {
                return nil
            }
            return WorkspaceSwitcherGroup(
                id: workspaceID,
                displayName: controller.currentConfig.workspace(for: workspaceID)?.displayName ?? workspaceID,
                windows: controller.windows(in: workspaceID).map(makeItem),
                preview: workspaceThumbnailCache.thumbnail(for: workspaceID),
                shortcutKey: shortcuts.key(for: workspaceID)
            )
        }
    }

    func refresh(
        windowIDs: Set<WindowID>,
        workspaceNames: Set<String>,
        priorityIDs: [WindowID] = []
    ) {
        let windows = controller.currentWindows()
        let liveWindowIDs = Set(windows.map(\.id))
        let liveWorkspaceNames = Set(controller.workspaces)

        windowThumbnailCache.removeStaleThumbnails(keeping: liveWindowIDs)
        workspaceThumbnailCache.removeStaleThumbnails(keeping: liveWorkspaceNames)
        refreshApplicationIcons(windows: windows)
        pendingWorkspaceNames.formUnion(workspaceNames.intersection(liveWorkspaceNames))
        windowThumbnailCache.refresh(windowIDs: orderedWindowIDs(
            windowIDs.intersection(liveWindowIDs),
            windows: windows,
            priorityIDs: priorityIDs
        ))

        if !windowThumbnailCache.isRefreshing {
            flushPendingWorkspaceThumbnails()
        }
    }

    func refreshWorkspaces(names: Set<String>) {
        let liveWorkspaceNames = Set(controller.workspaces)
        let names = names.intersection(liveWorkspaceNames)
        workspaceThumbnailCache.removeStaleThumbnails(keeping: liveWorkspaceNames)
        workspaceThumbnailCache.refresh(
            groups: workspaceGroups(ids: controller.workspaces.filter(names.contains)),
            displayBounds: controller.monitorSlots.map(\.display.frame)
        )
    }

    func refreshAll(priorityIDs: [WindowID] = []) {
        let windows = controller.currentWindows()
        refresh(
            windowIDs: Set(windows.map(\.id)),
            workspaceNames: Set(controller.workspaces),
            priorityIDs: priorityIDs
        )
    }

    private func flushPendingWorkspaceThumbnails() {
        guard !pendingWorkspaceNames.isEmpty else {
            return
        }

        let workspaceNames = pendingWorkspaceNames
        pendingWorkspaceNames.removeAll()
        refreshWorkspaces(names: workspaceNames)
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

    private func refreshApplicationIcons(windows: [WindowSnapshot]) {
        applicationIconCache.refresh(pids: Set(windows.map(\.app.pid)))
    }

    private func handleApplicationIconUpdated(_ pid: pid_t) {
        let windowIDs = Set(controller.currentWindows().filter { $0.app.pid == pid }.map(\.id))
        guard !windowIDs.isEmpty else {
            return
        }

        notify(windowIDs: windowIDs)
        pendingWorkspaceNames.formUnion(windowIDs.compactMap(controller.membership(for:)))
        if !windowThumbnailCache.isRefreshing {
            flushPendingWorkspaceThumbnails()
        }
    }

    private func notify(
        windowIDs: Set<WindowID> = [],
        workspaceNames: Set<String> = []
    ) {
        pendingUpdatedWindowIDs.formUnion(windowIDs)
        pendingUpdatedWorkspaceNames.formUnion(workspaceNames)
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
                workspaceNames: pendingUpdatedWorkspaceNames
            )
            pendingUpdatedWindowIDs.removeAll()
            pendingUpdatedWorkspaceNames.removeAll()
            isUpdateNotificationScheduled = false
            onUpdate?(update)
        }
    }
}
