import CoreGraphics
@testable import KkaciCore
import XCTest

final class DisplayGeometryTests: XCTestCase {
    func testContainingDisplayWins() {
        let displays = [
            display(id: 1, x: 0, width: 1000),
            display(id: 2, x: 1000, width: 1000)
        ]

        XCTAssertEqual(
            DisplayGeometry.display(containingOrNearest: CGPoint(x: 1200, y: 500), among: displays)?.id,
            2
        )
    }

    func testNearestDisplayUsesDistanceToTheDisplayBounds() {
        let displays = [
            display(id: 1, x: 0, width: 1000),
            display(id: 2, x: 1200, width: 100)
        ]

        XCTAssertEqual(
            DisplayGeometry.display(containingOrNearest: CGPoint(x: 1050, y: 500), among: displays)?.id,
            1
        )
    }

    func testNearestFrameIndexUsesDistanceToTheFrameBounds() {
        let frames = [
            CGRect(x: 0, y: 0, width: 1000, height: 1000),
            CGRect(x: 1200, y: 0, width: 100, height: 1000)
        ]

        XCTAssertEqual(
            DisplayGeometry.index(
                containingOrNearest: CGPoint(x: 1050, y: 500),
                among: frames
            ),
            0
        )
    }

    func testClampKeepsAWindowInsideTheTargetBounds() {
        let bounds = CGRect(x: 100, y: 200, width: 800, height: 600)

        XCTAssertEqual(
            DisplayGeometry.clamp(
                CGPoint(x: 850, y: 750),
                size: CGSize(width: 200, height: 100),
                inside: bounds
            ),
            CGPoint(x: 700, y: 700)
        )
    }

    func testClampPinsAnOversizedWindowToTheTargetOrigin() {
        let bounds = CGRect(x: 100, y: 200, width: 800, height: 600)

        XCTAssertEqual(
            DisplayGeometry.clamp(
                CGPoint(x: 500, y: 500),
                size: CGSize(width: 1000, height: 900),
                inside: bounds
            ),
            bounds.origin
        )
    }

    private func display(id: CGDirectDisplayID, x: CGFloat, width: CGFloat) -> DisplaySnapshot {
        let frame = CGRect(x: x, y: 0, width: width, height: 1000)
        return DisplaySnapshot(id: id, frame: frame, visibleFrame: frame, role: id == 1 ? .main : .extended)
    }
}
