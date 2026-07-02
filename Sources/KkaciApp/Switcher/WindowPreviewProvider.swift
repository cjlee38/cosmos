import AppKit
import KkaciCore

final class WindowPreviewProvider {
    private let thumbnailCache: WindowThumbnailCache

    init(thumbnailCache: WindowThumbnailCache) {
        self.thumbnailCache = thumbnailCache
    }

    func makeItem(for window: WindowSnapshot) -> WindowSwitcherItem {
        WindowSwitcherItem(
            id: window.id,
            appName: window.app.name,
            title: window.title,
            preview: thumbnailCache.thumbnail(for: window.id),
            icon: icon(for: window.app.pid)
        )
    }

    private func icon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
