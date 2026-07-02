import AppKit
import CoreGraphics
import KkaciCore

final class WindowPreviewProvider {
    func makeItem(for window: WindowSnapshot, includeThumbnail: Bool) -> WindowSwitcherItem {
        WindowSwitcherItem(
            id: window.id,
            appName: window.app.name,
            title: window.title,
            preview: includeThumbnail ? thumbnail(for: window.id) : nil,
            icon: icon(for: window.app.pid)
        )
    }

    private func thumbnail(for id: WindowID) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            id,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        guard image.width > 2, image.height > 2 else {
            return nil
        }

        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    private func icon(for pid: pid_t) -> NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }
}
