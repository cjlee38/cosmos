import AppKit
import CoreGraphics
import Foundation

public struct DisplayProvider: DisplayProviding {
    public init() {}

    public func hidePoint(for frame: WindowFrame) -> CGPoint {
        let assignableDisplays = displays().filter(\.isWorkspaceAssignable)
        return hidePoint(for: frame, displays: assignableDisplays)
            ?? bottomRight(of: CGDisplayBounds(CGMainDisplayID()))
    }

    public func displays() -> [DisplaySnapshot] {
        let screensByDisplayID = screensByDisplayID()
        let mainDisplayID = CGMainDisplayID()
        return onlineDisplayIDs().compactMap { id in
            guard let role = role(for: id, mainDisplayID: mainDisplayID) else {
                return nil
            }
            let frame = CGDisplayBounds(id)
            let screen = screensByDisplayID[id]
            return DisplaySnapshot(
                id: id,
                name: screen?.localizedName ?? "Display \(id)",
                frame: frame,
                visibleFrame: screen.map { visibleFrame(for: $0, displayFrame: frame) },
                role: role
            )
        }
    }

    func hidePoint(for frame: WindowFrame, displays: [DisplaySnapshot]) -> CGPoint? {
        guard let display = DisplayGeometry.display(containingOrNearest: frame.center, among: displays) else {
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

    private func role(for id: DisplayID, mainDisplayID: DisplayID) -> DisplayRole? {
        let mirrorSource = CGDisplayMirrorsDisplay(id)
        if mirrorSource != kCGNullDirectDisplay {
            return .mirrored(source: mirrorSource)
        }
        guard CGDisplayIsActive(id) != 0 else {
            return nil
        }
        return id == mainDisplayID ? .main : .extended
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return [CGMainDisplayID()]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return [CGMainDisplayID()]
        }

        return Array(displays.prefix(Int(count)))
    }
}

private enum HideCorner {
    case bottomLeft
    case bottomRight
}
