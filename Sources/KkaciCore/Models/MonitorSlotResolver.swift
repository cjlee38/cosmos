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

struct MonitorSlotResolver {
    private let displayProvider: any DisplayProviding

    init(displayProvider: any DisplayProviding) {
        self.displayProvider = displayProvider
    }

    func slots() -> [MonitorSlotSnapshot] {
        orderedDisplays().enumerated().map { index, display in
            MonitorSlotSnapshot(slot: index + 1, display: display)
        }
    }

    func slot(containing frame: WindowFrame?) -> MonitorSlot {
        guard let frame else {
            return 1
        }

        return slot(containing: frame.center)
    }

    func display(for slot: MonitorSlot) -> DisplaySnapshot? {
        slots().first { $0.slot == slot }?.display
    }

    func translatedFrame(_ frame: WindowFrame, to slot: MonitorSlot) -> WindowFrame? {
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
            origin: DisplayGeometry.clamp(origin, size: size, inside: targetFrame),
            size: size
        )
    }

    private func slot(containing point: CGPoint) -> MonitorSlot {
        let slots = slots()
        guard let display = DisplayGeometry.display(
            containingOrNearest: point,
            among: slots.map(\.display)
        ) else {
            return 1
        }
        return slots.first(where: { $0.display.id == display.id })?.slot ?? 1
    }

    private func orderedDisplays() -> [DisplaySnapshot] {
        let displays = displayProvider.displays()
        guard let main = displays.first(where: \.isMain) ?? displays.first else {
            return []
        }

        let others = displays
            .filter { $0.id != main.id }
            .sorted { lhs, rhs in
                let lhsDistance = DisplayGeometry.distanceSquared(from: main.frame.center, to: lhs.frame.center)
                let rhsDistance = DisplayGeometry.distanceSquared(from: main.frame.center, to: rhs.frame.center)
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
}
