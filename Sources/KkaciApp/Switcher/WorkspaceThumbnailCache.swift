import AppKit
import KkaciCore

final class WorkspaceThumbnailCache {
    private var thumbnails: [String: NSImage] = [:]

    func thumbnail(for workspace: String) -> NSImage? {
        thumbnails[workspace]
    }

    func refresh(groups: [WorkspaceSwitcherGroup]) {
        thumbnails = Dictionary(uniqueKeysWithValues: groups.map { group in
            (group.name, WorkspaceThumbnailRenderer.render(group: group))
        })
    }
}

private enum WorkspaceThumbnailRenderer {
    static func render(group: WorkspaceSwitcherGroup) -> NSImage {
        let desktopBounds = desktopBounds(for: group)
        let size = imageSize(for: desktopBounds)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.black.withAlphaComponent(0.40).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let positionedWindows = group.windows.compactMap { item -> (WindowSwitcherItem, WindowFrame)? in
            item.frame.map { (item, $0) }
        }

        if positionedWindows.isEmpty {
            drawEmptyState(in: NSRect(origin: .zero, size: size))
        } else {
            // Rendering note: if cost becomes noticeable, consider front-to-back occlusion culling.
            for (item, frame) in positionedWindows.reversed() {
                drawWindow(item, frame: frame, desktopBounds: desktopBounds, imageSize: size)
            }
        }

        image.unlockFocus()
        return image
    }

    private static func drawWindow(
        _ item: WindowSwitcherItem,
        frame: WindowFrame,
        desktopBounds: CGRect,
        imageSize: NSSize
    ) {
        let windowRect = frame.rect
        let visibleRect = windowRect.intersection(desktopBounds)
        guard !visibleRect.isNull, visibleRect.width > 0, visibleRect.height > 0 else {
            return
        }

        let rect = previewFrame(for: visibleRect, desktopBounds: desktopBounds, imageSize: imageSize)
        guard rect.width >= 1, rect.height >= 1 else {
            return
        }

        let radius = min(8, rect.width / 6, rect.height / 6)
        NSColor.black.withAlphaComponent(0.50).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()

        if let preview = item.preview {
            preview.draw(
                in: rect,
                from: sourceRect(for: visibleRect, in: windowRect, imageSize: preview.size),
                operation: .sourceOver,
                fraction: 1.0
            )
        } else if let icon = item.icon {
            let iconRect = rect.insetBy(dx: rect.width * 0.30, dy: rect.height * 0.30)
            icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        } else {
            drawInitial(item.appName.first.map(String.init) ?? "?", in: rect)
        }

        NSColor.white.withAlphaComponent(0.18).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        border.lineWidth = 1
        border.stroke()
    }

    private static func previewFrame(
        for visibleRect: CGRect,
        desktopBounds: CGRect,
        imageSize: NSSize
    ) -> NSRect {
        let drawingBounds = NSRect(origin: .zero, size: imageSize).insetBy(dx: 10, dy: 10)
        let desktopWidth = max(desktopBounds.width, 1)
        let desktopHeight = max(desktopBounds.height, 1)
        let scale = min(drawingBounds.width / desktopWidth, drawingBounds.height / desktopHeight)
        let usedSize = NSSize(width: desktopWidth * scale, height: desktopHeight * scale)
        let origin = NSPoint(
            x: drawingBounds.midX - usedSize.width / 2,
            y: drawingBounds.midY - usedSize.height / 2
        )
        let size = CGSize(width: visibleRect.width * scale, height: visibleRect.height * scale)
        let originX = origin.x + (visibleRect.minX - desktopBounds.minX) * scale
        let yFromTop = (visibleRect.minY - desktopBounds.minY) * scale
        let originY = origin.y + usedSize.height - yFromTop - size.height

        return NSRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private static func sourceRect(for visibleRect: CGRect, in windowRect: CGRect, imageSize: NSSize) -> NSRect {
        let widthScale = imageSize.width / max(windowRect.width, 1)
        let heightScale = imageSize.height / max(windowRect.height, 1)
        let width = visibleRect.width * widthScale
        let height = visibleRect.height * heightScale
        let originX = (visibleRect.minX - windowRect.minX) * widthScale
        let yFromTop = (visibleRect.minY - windowRect.minY) * heightScale
        let originY = imageSize.height - yFromTop - height

        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private static func desktopBounds(for group: WorkspaceSwitcherGroup) -> CGRect {
        let windowFrames = group.windows.compactMap { $0.frame?.rect }
        let displays = activeDisplayBounds()
        let matchingDisplays = displays.filter { display in
            windowFrames.contains { frame in
                frame.intersects(display) || display.contains(frame.center)
            }
        }

        if let bounds = union(matchingDisplays) {
            return bounds
        }

        if let bounds = union(displays) {
            return bounds
        }

        return CGRect(x: 0, y: 0, width: 1280, height: 720)
    }

    private static func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }

        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    private static func imageSize(for desktopBounds: CGRect) -> NSSize {
        let aspect = max(0.75, min(2.4, desktopBounds.width / max(desktopBounds.height, 1)))
        let width: CGFloat = 960
        return NSSize(width: width, height: round(width / aspect))
    }

    private static func union(_ rects: [CGRect]) -> CGRect? {
        guard let first = rects.first else {
            return nil
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func drawEmptyState(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 28, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: rect.minX, y: rect.midY - 20, width: rect.width, height: 40)
        NSString(string: "No windows").draw(in: textRect, withAttributes: attributes)
    }

    private static func drawInitial(_ text: String, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(18, min(rect.width, rect.height) * 0.34), weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let textRect = NSRect(x: rect.minX, y: rect.midY - 18, width: rect.width, height: 36)
        NSString(string: text).draw(in: textRect, withAttributes: attributes)
    }
}

private extension WindowFrame {
    var rect: CGRect {
        CGRect(origin: origin, size: size)
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
