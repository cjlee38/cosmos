import AppKit
import CoreText
import KkaciCore

final class WorkspaceThumbnailCache {
    private let renderQueue = DispatchQueue(label: "kkaci.workspace-thumbnails", qos: .userInitiated)
    private var thumbnails: [String: NSImage] = [:]
    private var pendingGroups: [String: WorkspaceThumbnailRenderGroup] = [:]
    private var liveWorkspaceNames: Set<String> = []
    private var isRendering = false
    private var onThumbnailsUpdated: (() -> Void)?

    func thumbnail(for workspace: String) -> NSImage? {
        thumbnails[workspace]
    }

    func setUpdateHandler(_ handler: @escaping () -> Void) {
        onThumbnailsUpdated = handler
    }

    func removeStaleThumbnails(keeping workspaceNames: Set<String>) {
        liveWorkspaceNames = workspaceNames
        thumbnails = thumbnails.filter { workspaceNames.contains($0.key) }
        pendingGroups = pendingGroups.filter { workspaceNames.contains($0.key) }
    }

    func refresh(groups: [WorkspaceSwitcherGroup]) {
        for group in WorkspaceThumbnailRenderer.makeRenderGroups(groups) {
            pendingGroups[group.name] = group
        }
        startPendingRender()
    }

    private func startPendingRender() {
        guard !isRendering, !pendingGroups.isEmpty else {
            return
        }

        let groups = Array(pendingGroups.values)
        pendingGroups.removeAll()
        isRendering = true
        renderQueue.async { [weak self] in
            let rendered = WorkspaceThumbnailRenderer.render(groups)
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                let images = rendered
                    .filter { self.liveWorkspaceNames.contains($0.key) }
                    .mapValues { image in
                        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    }
                self.thumbnails.merge(images) { _, new in new }
                self.isRendering = false
                self.onThumbnailsUpdated?()
                self.startPendingRender()
            }
        }
    }
}

private struct WorkspaceThumbnailRenderGroup {
    let name: String
    let desktopBounds: CGRect
    let windows: [WorkspaceThumbnailRenderWindow]
}

private struct WorkspaceThumbnailRenderWindow {
    let appInitial: String
    let frame: CGRect
    let preview: CGImage?
    let icon: CGImage?
}

private enum WorkspaceThumbnailRenderer {
    static func makeRenderGroups(_ groups: [WorkspaceSwitcherGroup]) -> [WorkspaceThumbnailRenderGroup] {
        let displays = activeDisplayBounds()
        return groups.map { group in
            let windows = group.windows.compactMap { item -> WorkspaceThumbnailRenderWindow? in
                guard let frame = item.frame?.rect else {
                    return nil
                }
                return WorkspaceThumbnailRenderWindow(
                    appInitial: item.appName.first.map(String.init) ?? "?",
                    frame: frame,
                    preview: item.preview?.cgImageValue,
                    icon: item.icon?.cgImageValue
                )
            }
            return WorkspaceThumbnailRenderGroup(
                name: group.name,
                desktopBounds: desktopBounds(windowFrames: windows.map(\.frame), displays: displays),
                windows: windows
            )
        }
    }

    static func render(_ groups: [WorkspaceThumbnailRenderGroup]) -> [String: CGImage] {
        Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            render(group).map { (group.name, $0) }
        })
    }

    private static func render(_ group: WorkspaceThumbnailRenderGroup) -> CGImage? {
        let size = imageSize(for: group.desktopBounds)
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let imageRect = CGRect(origin: .zero, size: size)
        context.setFillColor(CGColor(gray: 0, alpha: 0.40))
        context.fill(imageRect)

        if group.windows.isEmpty {
            drawText("No windows", size: 28, color: CGColor(gray: 0.65, alpha: 1), in: imageRect, context: context)
        } else {
            // Rendering note: if cost becomes noticeable, consider front-to-back occlusion culling.
            for window in group.windows.reversed() {
                drawWindow(window, desktopBounds: group.desktopBounds, imageSize: size, context: context)
            }
        }

        return context.makeImage()
    }

    private static func drawWindow(
        _ window: WorkspaceThumbnailRenderWindow,
        desktopBounds: CGRect,
        imageSize: CGSize,
        context: CGContext
    ) {
        let visibleWindowRect = window.frame.intersection(desktopBounds)
        guard !visibleWindowRect.isNull, visibleWindowRect.width > 0, visibleWindowRect.height > 0 else {
            return
        }

        let visiblePreviewRect = previewFrame(
            for: visibleWindowRect,
            desktopBounds: desktopBounds,
            imageSize: imageSize
        )
        guard visiblePreviewRect.width >= 1, visiblePreviewRect.height >= 1 else {
            return
        }

        let radius = min(8, visiblePreviewRect.width / 6, visiblePreviewRect.height / 6)
        let clipPath = CGPath(
            roundedRect: visiblePreviewRect,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        context.setFillColor(CGColor(gray: 0, alpha: 0.50))
        context.fill(visiblePreviewRect)

        drawWindowContent(
            window,
            visiblePreviewRect: visiblePreviewRect,
            fullPreviewRect: previewFrame(for: window.frame, desktopBounds: desktopBounds, imageSize: imageSize),
            context: context
        )
        context.restoreGState()

        context.addPath(clipPath)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.18))
        context.setLineWidth(1)
        context.strokePath()
    }

    private static func drawWindowContent(
        _ window: WorkspaceThumbnailRenderWindow,
        visiblePreviewRect: CGRect,
        fullPreviewRect: CGRect,
        context: CGContext
    ) {
        if let preview = window.preview {
            context.interpolationQuality = .high
            context.draw(preview, in: fullPreviewRect)
        } else if let icon = window.icon {
            let iconRect = visiblePreviewRect.insetBy(
                dx: visiblePreviewRect.width * 0.30,
                dy: visiblePreviewRect.height * 0.30
            )
            context.interpolationQuality = .high
            context.draw(icon, in: iconRect)
        } else {
            drawText(
                window.appInitial,
                size: max(18, min(visiblePreviewRect.width, visiblePreviewRect.height) * 0.34),
                color: CGColor(gray: 1, alpha: 1),
                in: visiblePreviewRect,
                context: context
            )
        }
    }

    private static func previewFrame(
        for windowRect: CGRect,
        desktopBounds: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        let drawingBounds = CGRect(origin: .zero, size: imageSize).insetBy(dx: 10, dy: 10)
        let desktopWidth = max(desktopBounds.width, 1)
        let desktopHeight = max(desktopBounds.height, 1)
        let scale = min(drawingBounds.width / desktopWidth, drawingBounds.height / desktopHeight)
        let usedSize = CGSize(width: desktopWidth * scale, height: desktopHeight * scale)
        let origin = CGPoint(
            x: drawingBounds.midX - usedSize.width / 2,
            y: drawingBounds.midY - usedSize.height / 2
        )
        let size = CGSize(width: windowRect.width * scale, height: windowRect.height * scale)
        let originX = origin.x + (windowRect.minX - desktopBounds.minX) * scale
        let yFromTop = (windowRect.minY - desktopBounds.minY) * scale
        let originY = origin.y + usedSize.height - yFromTop - size.height

        return CGRect(x: originX, y: originY, width: size.width, height: size.height)
    }

    private static func desktopBounds(windowFrames: [CGRect], displays: [CGRect]) -> CGRect {
        let matchingDisplays = displays.filter { display in
            windowFrames.contains { frame in
                frame.intersects(display) || display.contains(frame.center)
            }
        }
        return union(matchingDisplays)
            ?? union(displays)
            ?? CGRect(x: 0, y: 0, width: 1280, height: 720)
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

    private static func imageSize(for desktopBounds: CGRect) -> CGSize {
        let aspect = max(0.75, min(2.4, desktopBounds.width / max(desktopBounds.height, 1)))
        let width: CGFloat = 960
        return CGSize(width: width, height: round(width / aspect))
    }

    private static func union(_ rects: [CGRect]) -> CGRect? {
        guard let first = rects.first else {
            return nil
        }
        return rects.dropFirst().reduce(first) { $0.union($1) }
    }

    private static func drawText(
        _ text: String,
        size: CGFloat,
        color: CGColor,
        in rect: CGRect,
        context: CGContext
    ) {
        let font = CTFontCreateWithName("SF Pro Display" as CFString, size, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes as [NSAttributedString.Key: Any])
        )
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(
            x: rect.midX - bounds.width / 2 - bounds.minX,
            y: rect.midY - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, context)
    }
}

private extension NSImage {
    var cgImageValue: CGImage? {
        var proposedRect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
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
