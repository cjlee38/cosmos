import CoreGraphics
@testable import KkaciCore
import XCTest

final class DisplayProviderTests: XCTestCase {
    func testUsesBottomLeftWhenAnotherDisplayBlocksTheRightEdge() throws {
        let provider = DisplayProvider()
        let point = try XCTUnwrap(provider.hidePoint(
            for: .frame(x: 100, y: 100, width: 300, height: 200),
            displays: [
                display(id: 1, x: 0, y: 0),
                display(id: 2, x: 1000, y: 0)
            ]
        ))

        XCTAssertEqual(point, CGPoint(x: -299, y: 999))
    }

    func testUsesBottomRightWhenAnotherDisplayBlocksTheLeftEdge() throws {
        let provider = DisplayProvider()
        let point = try XCTUnwrap(provider.hidePoint(
            for: .frame(x: 1100, y: 100, width: 300, height: 200),
            displays: [
                display(id: 1, x: 0, y: 0),
                display(id: 2, x: 1000, y: 0)
            ]
        ))

        XCTAssertEqual(point, CGPoint(x: 1999, y: 999))
    }

    func testDiagonalDisplayObstructionUsesTheOtherCorner() throws {
        let provider = DisplayProvider()
        let point = try XCTUnwrap(provider.hidePoint(
            for: .frame(x: 100, y: 100, width: 300, height: 200),
            displays: [
                display(id: 1, x: 0, y: 0),
                display(id: 2, x: 1000, y: 1000)
            ]
        ))

        XCTAssertEqual(point, CGPoint(x: -299, y: 999))
    }

    func testParkingPointUsesTheSelectedDisplaysVisibleFrame() throws {
        let provider = DisplayProvider()
        let point = try XCTUnwrap(provider.hidePoint(
            for: .frame(x: 100, y: 100, width: 300, height: 200),
            displays: [
                DisplaySnapshot(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                    visibleFrame: CGRect(x: 0, y: 24, width: 1000, height: 900),
                    isMain: true
                )
            ]
        ))

        XCTAssertEqual(point, CGPoint(x: 999, y: 923))
    }

    private func display(id: UInt32, x: CGFloat, y: CGFloat) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            frame: CGRect(x: x, y: y, width: 1000, height: 1000),
            isMain: id == 1
        )
    }
}
