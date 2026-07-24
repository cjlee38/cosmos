import CoreGraphics
@testable import CosmosCore
import XCTest

final class DisplayProviderTests: XCTestCase {
    func testUsesBottomLeftWhenAnotherDisplayBlocksTheRightEdge() throws {
        let provider = WindowParkingPointProvider(displayProvider: FakeDisplayProvider())
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
        let provider = WindowParkingPointProvider(displayProvider: FakeDisplayProvider())
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
        let provider = WindowParkingPointProvider(displayProvider: FakeDisplayProvider())
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
        let provider = WindowParkingPointProvider(displayProvider: FakeDisplayProvider())
        let point = try XCTUnwrap(provider.hidePoint(
            for: .frame(x: 100, y: 100, width: 300, height: 200),
            displays: [
                DisplaySnapshot(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                    visibleFrame: CGRect(x: 0, y: 24, width: 1000, height: 900),
                    role: .main
                )
            ]
        ))

        XCTAssertEqual(point, CGPoint(x: 999, y: 923))
    }

    func testRecognizesExactParkingPositionsOnEitherDisplay() throws {
        let displays = [
            display(id: 1, x: 0, y: 0),
            display(id: 2, x: 1000, y: 0)
        ]
        let provider = WindowParkingPointProvider(
            displayProvider: FakeDisplayProvider(snapshots: displays)
        )

        XCTAssertTrue(provider.isHidePosition(
            .frame(x: -299, y: 999, width: 300, height: 200),
            displays: displays
        ))
        XCTAssertTrue(provider.isHidePosition(
            .frame(x: 1999, y: 999, width: 300, height: 200),
            displays: displays
        ))
    }

    func testRecognizesParkingStripsWithDifferentVisibleTitleBarHeights() {
        let displays = [
            display(id: 1, x: 0, y: 0),
            display(id: 2, x: 1000, y: 0)
        ]
        let provider = WindowParkingPointProvider(
            displayProvider: FakeDisplayProvider(snapshots: displays)
        )

        XCTAssertTrue(provider.isHidePosition(
            .frame(x: -299, y: 972, width: 300, height: 200),
            displays: displays
        ))
        XCTAssertTrue(provider.isHidePosition(
            .frame(x: 1999, y: 968, width: 300, height: 200),
            displays: displays
        ))
    }

    func testDoesNotTreatPositionNearParkingPointAsHidden() throws {
        let displays = [
            display(id: 1, x: 0, y: 0),
            display(id: 2, x: 1000, y: 0)
        ]
        let provider = WindowParkingPointProvider(
            displayProvider: FakeDisplayProvider(snapshots: displays)
        )

        XCTAssertFalse(provider.isHidePosition(
            .frame(x: 1998, y: 999, width: 300, height: 200),
            displays: displays
        ))
    }

    func testDoesNotTreatOnePixelCrossDisplayOverlapAsParking() {
        let displays = [
            display(id: 1, x: 0, y: 0),
            display(id: 2, x: 1000, y: 0)
        ]
        let provider = WindowParkingPointProvider(
            displayProvider: FakeDisplayProvider(snapshots: displays)
        )

        XCTAssertFalse(provider.isHidePosition(
            .frame(x: 999, y: 800, width: 300, height: 300),
            displays: displays
        ))
    }

    func testDoesNotTreatOnePixelOverlapAtObstructedParkingCornerAsParking() {
        let displays = [
            display(id: 1, x: 0, y: 0),
            display(id: 2, x: -1000, y: 0),
            display(id: 3, x: 1000, y: 0)
        ]
        let provider = WindowParkingPointProvider(
            displayProvider: FakeDisplayProvider(snapshots: displays)
        )

        XCTAssertFalse(provider.isHidePosition(
            .frame(x: 999, y: 800, width: 300, height: 300),
            displays: displays
        ))
    }

    func testParkingAssessmentIsSafeWhenEitherBottomCornerIsOpen() {
        let displays = [
            display(id: 1, x: 0, y: 0).frame,
            display(id: 2, x: 1000, y: 0).frame
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: displays[0],
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomLeft)
        XCTAssertTrue(assessment.hasUnobstructedCorner)
    }

    func testParkingAssessmentIsObstructedWhenBothBottomCornersAreBlocked() {
        let center = display(id: 1, x: 0, y: 0).frame
        let displays = [
            center,
            display(id: 2, x: -1000, y: 0).frame,
            display(id: 3, x: 1000, y: 0).frame
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: center,
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomRight)
        XCTAssertFalse(assessment.hasUnobstructedCorner)
    }

    private func display(id: UInt32, x: CGFloat, y: CGFloat) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            frame: CGRect(x: x, y: y, width: 1000, height: 1000),
            role: id == 1 ? .main : .extended
        )
    }
}
