import AppKit
import KkaciCore

struct WorkspaceThumbnailRenderGroup {
    let id: String
    let desktopBounds: CGRect
    let windows: [WorkspaceThumbnailRenderWindow]
}

struct WorkspaceThumbnailRenderWindow {
    let frame: CGRect
    let preview: CGImage?
}

enum WorkspaceThumbnailRenderer {
    static func makeRenderGroups(_ groups: [WorkspaceSwitcherGroup]) -> [WorkspaceThumbnailRenderGroup] {
        groups.map { group in
            let windows = group.windows.compactMap { item -> WorkspaceThumbnailRenderWindow? in
                guard let frame = item.frame?.rect else {
                    return nil
                }
                return WorkspaceThumbnailRenderWindow(
                    frame: frame,
                    preview: item.preview?.cgImageValue
                )
            }
            return WorkspaceThumbnailRenderGroup(
                id: group.id,
                desktopBounds: group.displayFrame,
                windows: windows
            )
        }
    }

    static func previewFrame(
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

    static func render(_ group: WorkspaceThumbnailRenderGroup) -> CGImage? {
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

        if !group.windows.isEmpty {
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
        fullPreviewRect: CGRect,
        context: CGContext
    ) {
        if let preview = window.preview {
            context.interpolationQuality = .high
            context.draw(preview, in: fullPreviewRect)
        }
    }

    private static func imageSize(for desktopBounds: CGRect) -> CGSize {
        let aspect = max(0.75, min(2.4, desktopBounds.width / max(desktopBounds.height, 1)))
        let width: CGFloat = 960
        return CGSize(width: width, height: round(width / aspect))
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
