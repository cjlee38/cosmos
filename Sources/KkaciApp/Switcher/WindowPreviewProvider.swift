import AppKit
import KkaciCore

final class WindowPreviewProvider {
    private let thumbnailCache: WindowThumbnailCache
    private let applicationIconCache: ApplicationIconCache

    init(thumbnailCache: WindowThumbnailCache, applicationIconCache: ApplicationIconCache) {
        self.thumbnailCache = thumbnailCache
        self.applicationIconCache = applicationIconCache
    }

    func makeItem(for window: WindowSnapshot, frame: WindowFrame?) -> WindowSwitcherItem {
        WindowSwitcherItem(
            windowID: window.id,
            appName: window.app.name,
            title: window.title,
            frame: frame,
            preview: thumbnailCache.thumbnail(for: window.id),
            icon: applicationIconCache.icon(for: window.app.pid)
        )
    }
}
