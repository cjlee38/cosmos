import KkaciCore

final class WindowThumbnailRefresher {
    let thumbnailCache: WindowThumbnailCache
    private let controller: WorkspaceController

    init(controller: WorkspaceController, thumbnailCache: WindowThumbnailCache) {
        self.controller = controller
        self.thumbnailCache = thumbnailCache
    }

    func refreshManagedThumbnails(
        priorityIDs: [WindowID] = [],
        onThumbnailUpdated: @escaping (WindowID) -> Void = { _ in }
    ) {
        let windows = controller.currentWindows().windows
        let managedWindows = windows.filter { controller.membership(for: $0.id) != nil }
        let managedIDs = Set(managedWindows.map(\.id))
        thumbnailCache.removeStaleThumbnails(keeping: Set(windows.map(\.id)))
        thumbnailCache.refresh(
            windows: managedWindows,
            priorityIDs: priorityIDs.filter { managedIDs.contains($0) },
            onThumbnailUpdated: onThumbnailUpdated
        )
    }
}
