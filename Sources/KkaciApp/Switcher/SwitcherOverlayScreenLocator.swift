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

        let screensWithBounds = screens.compactMap { screen in
            cgBounds(for: screen).map { (screen, $0) }
        }
        guard let index = DisplayGeometry.index(
            containingOrNearest: point,
            among: screensWithBounds.map(\.1)
        ) else {
            return NSScreen.main ?? screens[0]
        }
        return screensWithBounds[index].0
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
}
