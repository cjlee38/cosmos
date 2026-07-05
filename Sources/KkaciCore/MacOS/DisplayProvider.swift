import AppKit
import CoreGraphics
import Foundation

public struct DisplayProvider: DisplayProviding {
    public init() {}

    public func hidePoint(for frame: WindowFrame) -> CGPoint {
        let display = displayBounds(containing: frame.center) ?? CGDisplayBounds(CGMainDisplayID())
        return CGPoint(x: display.maxX - 1, y: display.maxY - 1)
    }

    public func displays() -> [DisplaySnapshot] {
        let screensByDisplayID = screensByDisplayID()
        return activeDisplayIDs().map { id in
            let frame = CGDisplayBounds(id)
            return DisplaySnapshot(
                id: id,
                frame: frame,
                visibleFrame: screensByDisplayID[id].map { visibleFrame(for: $0, displayFrame: frame) },
                isMain: id == CGMainDisplayID()
            )
        }
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
        activeDisplayIDs().map(CGDisplayBounds)
    }

    private func screensByDisplayID() -> [CGDirectDisplayID: NSScreen] {
        Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            guard let id = displayID(for: screen) else {
                return nil
            }
            return (id, screen)
        })
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    private func visibleFrame(for screen: NSScreen, displayFrame: CGRect) -> CGRect {
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        let leftInset = visibleFrame.minX - screenFrame.minX
        let rightInset = screenFrame.maxX - visibleFrame.maxX
        let bottomInset = visibleFrame.minY - screenFrame.minY
        let topInset = screenFrame.maxY - visibleFrame.maxY

        return CGRect(
            x: displayFrame.minX + leftInset,
            y: displayFrame.minY + topInset,
            width: displayFrame.width - leftInset - rightInset,
            height: displayFrame.height - topInset - bottomInset
        )
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return [CGMainDisplayID()]
        }

        return Array(displays.prefix(Int(count)))
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
