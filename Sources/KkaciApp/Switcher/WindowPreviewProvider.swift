import AppKit
import KkaciCore

final class WindowPreviewProvider {
    private let thumbnailCache: WindowThumbnailCache

    init(thumbnailCache: WindowThumbnailCache) {
        self.thumbnailCache = thumbnailCache
    }

    func makeItem(for window: WindowSnapshot, frame: WindowFrame?) -> WindowSwitcherItem {
        WindowSwitcherItem(
            id: window.id,
            appName: window.app.name,
            title: window.title,
            frame: frame,
            preview: thumbnailCache.thumbnail(for: window.id),
            icon: icon(for: window.app.pid)
        )
    }

    private func icon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
