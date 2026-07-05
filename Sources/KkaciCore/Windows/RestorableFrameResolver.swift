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

        if displays.contains(where: { $0.frame.contains(frame.center) }) {
            return frame
        }

        guard let target = nearestDisplay(to: frame.center, in: displays),
              target.visibleFrame.width > 0,
              target.visibleFrame.height > 0
        else {
            return frame
        }

        return WindowFrame(
            origin: clamp(frame.origin, size: frame.size, inside: target.visibleFrame),
            size: frame.size
        )
    }

    private func nearestDisplay(to point: CGPoint, in displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        displays.min { lhs, rhs in
            distanceSquared(from: point, to: lhs.frame) < distanceSquared(from: point, to: rhs.frame)
        }
    }

    private func clamp(_ origin: CGPoint, size: CGSize, inside rect: CGRect) -> CGPoint {
        CGPoint(
            x: clamp(origin.x, length: size.width, min: rect.minX, max: rect.maxX),
            y: clamp(origin.y, length: size.height, min: rect.minY, max: rect.maxY)
        )
    }

    private func clamp(_ value: CGFloat, length: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard length <= maxValue - minValue else {
            return minValue
        }
        return min(max(value, minValue), maxValue - length)
    }

    private func distanceSquared(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
