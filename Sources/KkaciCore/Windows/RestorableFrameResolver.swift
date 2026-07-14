import CoreGraphics
import Foundation

final class RestorableFrameResolver {
    private let displayProvider: any DisplayProviding

    init(displayProvider: any DisplayProviding) {
        self.displayProvider = displayProvider
    }

    func frameForRestore(_ frame: WindowFrame) -> WindowFrame {
        let displays = displayProvider.displays()
        guard !displays.isEmpty else {
            return frame
        }

        guard let target = DisplayGeometry.display(
            containingOrNearest: frame.center,
            among: displays
        ) else {
            return frame
        }
        if target.frame.contains(frame.center) {
            return frame
        }
        guard target.visibleFrame.width > 0,
              target.visibleFrame.height > 0
        else {
            return frame
        }

        return WindowFrame(
            origin: DisplayGeometry.clamp(frame.origin, size: frame.size, inside: target.visibleFrame),
            size: frame.size
        )
    }
}
