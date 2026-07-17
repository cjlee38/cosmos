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

public struct DisplayTopologySnapshot: Equatable {
    public let displays: [DisplaySnapshot]
    public let monitorSlots: [MonitorSlotSnapshot]

    public init(displays: [DisplaySnapshot], monitorSlots: [MonitorSlotSnapshot]) {
        self.displays = displays
        self.monitorSlots = monitorSlots
    }

    public static let empty = DisplayTopologySnapshot(displays: [], monitorSlots: [])

    public var availableMonitorSlots: Set<MonitorSlot> {
        Set(monitorSlots.map(\.slot))
    }
}

public enum WorkspaceDisplayAssignment {
    public static func monitorSlot(
        for displayID: DisplayID,
        monitorSlots: [MonitorSlotSnapshot]
    ) throws -> MonitorSlot {
        guard let monitorSlot = monitorSlots.first(where: { $0.display.id == displayID })?.slot else {
            throw WorkspaceError.displayNotFound(displayID)
        }
        return monitorSlot
    }
}

public struct MonitorSlotResolver {
    private let displayProvider: any DisplayProviding

    public init(displayProvider: any DisplayProviding) {
        self.displayProvider = displayProvider
    }

    public func topology() -> DisplayTopologySnapshot {
        let displays = displayProvider.displays()
        return DisplayTopologySnapshot(
            displays: displays,
            monitorSlots: slots(for: displays)
        )
    }

    public func slots() -> [MonitorSlotSnapshot] {
        topology().monitorSlots
    }

    func slots(for displays: [DisplaySnapshot]) -> [MonitorSlotSnapshot] {
        orderedDisplays(in: displays).enumerated().map { index, display in
            MonitorSlotSnapshot(slot: index + 1, display: display)
        }
    }

    func slot(containing frame: WindowFrame?) -> MonitorSlot {
        slot(containing: frame, among: slots())
    }

    func slot(containing frame: WindowFrame?, among slots: [MonitorSlotSnapshot]) -> MonitorSlot {
        guard let frame else {
            return 1
        }

        return slot(containing: frame.center, among: slots)
    }

    func display(for slot: MonitorSlot, among slots: [MonitorSlotSnapshot]) -> DisplaySnapshot? {
        slots.first { $0.slot == slot }?.display
    }

    func translatedFrame(_ frame: WindowFrame, to slot: MonitorSlot) -> WindowFrame? {
        translatedFrame(frame, to: slot, among: slots())
    }

    func translatedFrame(
        _ frame: WindowFrame,
        to slot: MonitorSlot,
        among slots: [MonitorSlotSnapshot]
    ) -> WindowFrame? {
        guard let source = display(for: self.slot(containing: frame, among: slots), among: slots),
              let target = display(for: slot, among: slots)
        else {
            return nil
        }

        return translatedFrame(frame, from: source, to: target)
    }

    func translatedFrame(
        _ frame: WindowFrame,
        from source: DisplaySnapshot,
        to target: DisplaySnapshot
    ) -> WindowFrame? {
        if source.id == target.id, source.visibleFrame == target.visibleFrame {
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

    private func slot(containing point: CGPoint, among slots: [MonitorSlotSnapshot]) -> MonitorSlot {
        guard let display = DisplayGeometry.display(
            containingOrNearest: point,
            among: slots.map(\.display)
        ) else {
            return 1
        }
        return slots.first(where: { $0.display.id == display.id })?.slot ?? 1
    }

    private func orderedDisplays(in displays: [DisplaySnapshot]) -> [DisplaySnapshot] {
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
