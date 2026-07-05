import CoreGraphics
import Foundation

public typealias MonitorSlot = Int

public struct MonitorSlotSnapshot: Equatable {
    public let slot: MonitorSlot
    public let display: DisplaySnapshot

    public init(slot: MonitorSlot, display: DisplaySnapshot) {
        self.slot = slot
        self.display = display
    }
}

public struct MonitorSlotResolver {
    private let displayProvider: any DisplayProviding

    public init(displayProvider: any DisplayProviding) {
        self.displayProvider = displayProvider
    }

    public func slots() -> [MonitorSlotSnapshot] {
        orderedDisplays().enumerated().map { index, display in
            MonitorSlotSnapshot(slot: index + 1, display: display)
        }
    }

    public func slot(containing frame: WindowFrame?) -> MonitorSlot {
        guard let frame else {
            return 1
        }

        return slot(containing: frame.center)
    }

    public func display(for slot: MonitorSlot) -> DisplaySnapshot? {
        slots().first { $0.slot == slot }?.display
    }

    public func translatedFrame(_ frame: WindowFrame, to slot: MonitorSlot) -> WindowFrame? {
        guard let source = display(for: self.slot(containing: frame)),
              let target = display(for: slot),
              source.id != target.id
        else {
            return nil
        }

        let sourceFrame = source.visibleFrame
        let targetFrame = target.visibleFrame

        guard sourceFrame.width > 0, sourceFrame.height > 0 else {
            return nil
        }

        let scale = CGSize(
            width: targetFrame.width / sourceFrame.width,
            height: targetFrame.height / sourceFrame.height
        )
        let size = CGSize(
            width: frame.size.width * scale.width,
            height: frame.size.height * scale.height
        )
        let origin = CGPoint(
            x: targetFrame.minX + (frame.origin.x - sourceFrame.minX) * scale.width,
            y: targetFrame.minY + (frame.origin.y - sourceFrame.minY) * scale.height
        )
        return WindowFrame(
            origin: clamp(origin, size: size, inside: targetFrame),
            size: size
        )
    }

    private func slot(containing point: CGPoint) -> MonitorSlot {
        let slots = slots()
        if let containing = slots.first(where: { $0.display.frame.contains(point) }) {
            return containing.slot
        }

        return slots.min { lhs, rhs in
            distanceSquared(from: point, to: lhs.display.frame) < distanceSquared(from: point, to: rhs.display.frame)
        }?.slot ?? 1
    }

    private func orderedDisplays() -> [DisplaySnapshot] {
        let displays = displayProvider.displays()
        guard let main = displays.first(where: \.isMain) ?? displays.first else {
            return []
        }

        let others = displays
            .filter { $0.id != main.id }
            .sorted { lhs, rhs in
                let lhsDistance = distanceSquared(from: main.frame.center, to: lhs.frame.center)
                let rhsDistance = distanceSquared(from: main.frame.center, to: rhs.frame.center)
                if lhsDistance != rhsDistance {
                    return lhsDistance < rhsDistance
                }
                if lhs.frame.minX != rhs.frame.minX {
                    return lhs.frame.minX < rhs.frame.minX
                }
                return lhs.frame.minY < rhs.frame.minY
            }

        return [main] + others
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
