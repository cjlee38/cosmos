import AppKit
import CoreGraphics
import Foundation

public struct DisplayProvider: DisplayProviding {
    public init() {}

    public func displays() throws -> [DisplaySnapshot] {
        let screensByDisplayID = screensByDisplayID()
        let mainDisplayID = CGMainDisplayID()
        return try onlineDisplayIDs().compactMap { id in
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
}

public struct WindowParkingPointProvider: HidePointProviding {
    private let displayProvider: any DisplayProviding

    public init(displayProvider: any DisplayProviding) {
        self.displayProvider = displayProvider
    }

    public func hidePoint(for frame: WindowFrame) throws -> CGPoint {
        guard let point = try hidePoint(for: frame, displays: displayProvider.displays()) else {
            throw DisplayProviderError.noActiveDisplays
        }
        return point
    }

    public func isHidePosition(_ frame: WindowFrame, displays: [DisplaySnapshot]) -> Bool {
        return displays.contains { display in
            let visibleFrame = display.visibleFrame
            let windowFrame = CGRect(origin: frame.origin, size: frame.size)
            let intersection = windowFrame.intersection(visibleFrame)
            let assessment = Self.assessment(for: display.frame, among: displays.map(\.frame))
            guard assessment.hasUnobstructedCorner,
                  !intersection.isNull,
                  intersection.width == 1,
                  intersection.maxY == visibleFrame.maxY,
                  windowFrame.maxY > visibleFrame.maxY
            else {
                return false
            }

            switch assessment.corner {
            case .bottomLeft:
                return intersection.minX == visibleFrame.minX
                    && windowFrame.minX < visibleFrame.minX
            case .bottomRight:
                return intersection.maxX == visibleFrame.maxX
                    && windowFrame.maxX > visibleFrame.maxX
            }
        }
    }

    func hidePoint(for frame: WindowFrame, displays: [DisplaySnapshot]) -> CGPoint? {
        guard let display = DisplayGeometry.display(containingOrNearest: frame.center, among: displays) else {
            return nil
        }
        return hidePoint(for: frame, on: display, among: displays)
    }

    public func hidePoint(
        for frame: WindowFrame,
        on display: DisplaySnapshot,
        among displays: [DisplaySnapshot]
    ) -> CGPoint {
        let visibleFrame = display.visibleFrame
        switch Self.assessment(for: display.frame, among: displays.map(\.frame)).corner {
        case .bottomLeft:
            return CGPoint(
                x: visibleFrame.minX - frame.size.width + 1,
                y: visibleFrame.maxY - 1
            )
        case .bottomRight:
            return bottomRight(of: visibleFrame)
        }
    }

    public static func assessment(
        for display: CGRect,
        among displays: [CGRect]
    ) -> WindowParkingAssessment {
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

        return WindowParkingAssessment(
            corner: leftScore < rightScore ? .bottomLeft : .bottomRight,
            hasUnobstructedCorner: leftScore == 0 || rightScore == 0
        )
    }

    private func bottomRight(of display: CGRect) -> CGPoint {
        CGPoint(x: display.maxX - 1, y: display.maxY - 1)
    }
}

public struct WindowParkingAssessment: Equatable {
    public let corner: WindowParkingCorner
    public let hasUnobstructedCorner: Bool
}

public enum WindowParkingCorner: Equatable {
    case bottomLeft
    case bottomRight
}

private extension DisplayProvider {
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
        guard CGDisplayIsActive(id) != 0,
              CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay
        else {
            return nil
        }
        return id == mainDisplayID ? .main : .extended
    }

    private func onlineDisplayIDs() throws -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        let countStatus = CGGetOnlineDisplayList(0, nil, &count)
        guard countStatus == .success else {
            throw DisplayProviderError.onlineDisplayListFailed(countStatus)
        }
        guard count > 0 else {
            throw DisplayProviderError.noActiveDisplays
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        let listStatus = CGGetOnlineDisplayList(count, &displays, &count)
        guard listStatus == .success else {
            throw DisplayProviderError.onlineDisplayListFailed(listStatus)
        }

        return Array(displays.prefix(Int(count)))
    }
}

private enum DisplayProviderError: Error, CustomStringConvertible {
    case onlineDisplayListFailed(CGError)
    case noActiveDisplays

    var description: String {
        switch self {
        case let .onlineDisplayListFailed(error):
            "CGGetOnlineDisplayList failed: \(error.rawValue)"
        case .noActiveDisplays:
            "No active displays were found."
        }
    }
}
