import AppKit
import CoreGraphics
import Foundation

public struct DisplayProvider: DisplayProviding {
    public init() {}

    public func hidePoint(for frame: WindowFrame) -> CGPoint {
        hidePoint(for: frame, displays: displays()) ?? bottomRight(of: CGDisplayBounds(CGMainDisplayID()))
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

    func hidePoint(for frame: WindowFrame, displays: [DisplaySnapshot]) -> CGPoint? {
        guard let display = display(containing: frame.center, among: displays) else {
            return nil
        }

        let visibleFrame = display.visibleFrame
        switch optimalHideCorner(for: display.frame, among: displays.map(\.frame)) {
        case .bottomLeft:
            return CGPoint(
                x: visibleFrame.minX - frame.size.width + 1,
                y: visibleFrame.maxY - 1
            )
        case .bottomRight:
            return bottomRight(of: visibleFrame)
        }
    }

    private func display(containing point: CGPoint, among displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        if let containing = displays.first(where: { $0.frame.contains(point) }) {
            return containing
        }

        return displays.min { lhs, rhs in
            distanceSquared(from: lhs.frame.center, to: point) < distanceSquared(from: rhs.frame.center, to: point)
        }
    }

    private func optimalHideCorner(for display: CGRect, among displays: [CGRect]) -> HideCorner {
        // Sample each corner's side, bottom, and diagonal; diagonal overlap is the strongest obstruction.
        let xOffset = display.width * 0.1
        let yOffset = display.height * 0.1

        func obstructionScore(side: CGPoint, bottom: CGPoint, diagonal: CGPoint) -> Int {
            displays.reduce(0) { score, candidate in
                score
                    + (candidate.contains(side) ? 1 : 0)
                    + (candidate.contains(bottom) ? 1 : 0)
                    + (candidate.contains(diagonal) ? 10 : 0)
            }
        }

        let bottomLeft = CGPoint(x: display.minX, y: display.maxY)
        let leftScore = obstructionScore(
            side: CGPoint(x: bottomLeft.x - 2, y: bottomLeft.y - yOffset),
            bottom: CGPoint(x: bottomLeft.x + xOffset, y: bottomLeft.y + 2),
            diagonal: CGPoint(x: bottomLeft.x - 2, y: bottomLeft.y + 2)
        )

        let bottomRight = CGPoint(x: display.maxX, y: display.maxY)
        let rightScore = obstructionScore(
            side: CGPoint(x: bottomRight.x + 2, y: bottomRight.y - yOffset),
            bottom: CGPoint(x: bottomRight.x - xOffset, y: bottomRight.y + 2),
            diagonal: CGPoint(x: bottomRight.x + 2, y: bottomRight.y + 2)
        )

        return leftScore < rightScore ? .bottomLeft : .bottomRight
    }

    private func bottomRight(of display: CGRect) -> CGPoint {
        CGPoint(x: display.maxX - 1, y: display.maxY - 1)
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

private enum HideCorner {
    case bottomLeft
    case bottomRight
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
