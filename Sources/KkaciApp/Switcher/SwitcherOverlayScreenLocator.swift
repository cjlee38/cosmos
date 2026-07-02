import AppKit
import CoreGraphics
import KkaciCore

final class SwitcherOverlayScreenLocator {
    func visibleFrame(for anchorFrame: WindowFrame?) -> NSRect {
        if let anchorFrame {
            return screen(containing: anchorFrame.center)?.visibleFrame ?? fallbackVisibleFrame()
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }?.visibleFrame
            ?? fallbackVisibleFrame()
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return NSScreen.main
        }

        if let containing = screens.first(where: { cgBounds(for: $0)?.contains(point) == true }) {
            return containing
        }

        return screens.min { lhs, rhs in
            guard let lhsBounds = cgBounds(for: lhs),
                  let rhsBounds = cgBounds(for: rhs)
            else {
                return false
            }
            return distanceSquared(from: lhsBounds.center, to: point) < distanceSquared(from: rhsBounds.center, to: point)
        } ?? NSScreen.main ?? screens[0]
    }

    private func fallbackVisibleFrame() -> NSRect {
        NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
    }

    private func cgBounds(for screen: NSScreen) -> CGRect? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDisplayBounds(CGDirectDisplayID(number.uint32Value))
    }

    private func distanceSquared(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
