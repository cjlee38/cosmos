import CoreGraphics
import Foundation

public struct DisplayProvider: HidePointProviding {
    public init() {}

    public func hidePoint(for frame: WindowFrame) -> CGPoint {
        let display = displayBounds(containing: frame.center) ?? CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: display.maxX - 1, y: display.maxY - 1)
    }

    private func displayBounds(containing point: CGPoint) -> CGRect? {
        let displays = activeDisplayBounds()
        if let containing = displays.first(where: { $0.contains(point) }) {
            return containing
        }

        return displays.min { lhs, rhs in
            distanceSquared(from: lhs.center, to: point) < distanceSquared(from: rhs.center, to: point)
        }
    }

    private func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return [CGDisplayBounds(CGMainDisplayID())]
        }

        return displays.prefix(Int(count)).map(CGDisplayBounds)
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
