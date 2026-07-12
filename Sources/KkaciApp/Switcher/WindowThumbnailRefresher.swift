import AppKit
import KkaciCore

final class WindowThumbnailRefresher {
    let windowThumbnailCache: WindowThumbnailCache
    let workspaceThumbnailCache: WorkspaceThumbnailCache
    let applicationIconCache: ApplicationIconCache
    private let controller: WorkspaceController
    private var workspaceThumbnailRefreshScheduled = false

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
    }

    func refreshWindowThumbnails(
        priorityIDs: [WindowID] = [],
        onThumbnailUpdated: @escaping (WindowID) -> Void = { _ in }
    ) {
        let windows = controller.currentWindows().windows
        refreshApplicationIcons(windows: windows, onWindowUpdated: onThumbnailUpdated)
        windowThumbnailCache.removeStaleThumbnails(keeping: Set(windows.map(\.id)))
        windowThumbnailCache.refresh(
            windows: windows,
            priorityIDs: priorityIDs,
            onThumbnailUpdated: onThumbnailUpdated
        )
    }

    func refreshWorkspaceThumbnails() {
        let windows = controller.currentWindows().windows
        workspaceThumbnailCache.refresh(groups: workspaceGroups(from: windows))
    }

    func refreshAllThumbnails(
        priorityIDs: [WindowID] = [],
        onThumbnailUpdated: @escaping (WindowID) -> Void = { _ in }
    ) {
        refreshWindowThumbnails(priorityIDs: priorityIDs) { [weak self] id in
            self?.scheduleWorkspaceThumbnailRefresh()
            onThumbnailUpdated(id)
        }
        refreshWorkspaceThumbnails()
    }

    private func scheduleWorkspaceThumbnailRefresh() {
        guard !workspaceThumbnailRefreshScheduled else {
            return
        }

        workspaceThumbnailRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            workspaceThumbnailRefreshScheduled = false
            refreshWorkspaceThumbnails()
        }
    }

    private func workspaceGroups(from windows: [WindowSnapshot]) -> [WorkspaceSwitcherGroup] {
        controller.workspaces.map { workspace in
            WorkspaceSwitcherGroup(
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

    private func refreshApplicationIcons(
        windows: [WindowSnapshot],
        onWindowUpdated: @escaping (WindowID) -> Void
    ) {
        let windowIDsByPID = Dictionary(grouping: windows, by: \.app.pid)
            .mapValues { $0.map(\.id) }
        applicationIconCache.refresh(pids: Set(windowIDsByPID.keys)) { pid in
            windowIDsByPID[pid]?.forEach(onWindowUpdated)
        }
    }
}
