import AppKit
import KkaciCore

final class WindowThumbnailRefresher {
    let windowThumbnailCache: WindowThumbnailCache
    let workspaceThumbnailCache: WorkspaceThumbnailCache
    let applicationIconCache: ApplicationIconCache
    private let controller: WorkspaceController
    private var pendingWorkspaceNames: Set<String> = []
    private var onWindowThumbnailUpdated: ((WindowID) -> Void)?

    init(
        controller: WorkspaceController,
        thumbnailCache windowThumbnailCache: WindowThumbnailCache,
        workspaceThumbnailCache: WorkspaceThumbnailCache,
        applicationIconCache: ApplicationIconCache
    ) {
        self.controller = controller
        self.windowThumbnailCache = windowThumbnailCache
        self.workspaceThumbnailCache = workspaceThumbnailCache
        self.applicationIconCache = applicationIconCache
        windowThumbnailCache.setUpdateHandlers(
            onThumbnailUpdated: { [weak self] windowID in
                self?.onWindowThumbnailUpdated?(windowID)
            },
            onCaptureCycleCompleted: { [weak self] in
                self?.flushPendingWorkspaceThumbnails()
            }
        )
    }

    func setWindowThumbnailUpdateHandler(_ handler: @escaping (WindowID) -> Void) {
        onWindowThumbnailUpdated = handler
    }

    func refreshThumbnails(
        windowIDs: Set<WindowID>,
        workspaceNames: Set<String>,
        priorityIDs: [WindowID] = []
    ) {
        let windows = controller.currentWindows().windows
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

    func refreshWorkspaceThumbnails(names: Set<String>) {
        let windows = controller.currentWindows().windows
        let liveWorkspaceNames = Set(controller.workspaces)
        workspaceThumbnailCache.removeStaleThumbnails(keeping: liveWorkspaceNames)
        workspaceThumbnailCache.refresh(groups: workspaceGroups(
            from: windows,
            names: names.intersection(liveWorkspaceNames)
        ))
    }

    func refreshAllThumbnails(priorityIDs: [WindowID] = []) {
        let windows = controller.currentWindows().windows
        refreshThumbnails(
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
        refreshWorkspaceThumbnails(names: workspaceNames)
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

    private func workspaceGroups(
        from windows: [WindowSnapshot],
        names: Set<String>
    ) -> [WorkspaceSwitcherGroup] {
        controller.workspaces.compactMap { workspace in
            guard names.contains(workspace) else {
                return nil
            }
            return WorkspaceSwitcherGroup(
                name: workspace,
                windows: windows
                    .filter { controller.membership(for: $0.id) == workspace && !$0.isMinimized }
                    .map(makeItem),
                preview: nil
            )
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
        let windowsByPID = Dictionary(grouping: windows, by: \.app.pid)
        applicationIconCache.refresh(pids: Set(windowsByPID.keys)) { [weak self] pid in
            guard let self, let windows = windowsByPID[pid] else {
                return
            }

            let windowIDs = windows.map(\.id)
            windowIDs.forEach { self.onWindowThumbnailUpdated?($0) }
            pendingWorkspaceNames.formUnion(windowIDs.compactMap(controller.membership(for:)))
            if !windowThumbnailCache.isRefreshing {
                flushPendingWorkspaceThumbnails()
            }
        }
    }
}
