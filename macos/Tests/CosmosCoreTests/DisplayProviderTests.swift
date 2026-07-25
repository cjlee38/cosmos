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

    func testRecognizesExactParkingPositionsOnEitherDisplay() {
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

    func testDoesNotTreatPositionNearParkingPointAsHidden() {
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
            display(id: 1, x: 0, y: 0),
            display(id: 2, x: 1000, y: 0)
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: displays[0],
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomLeft)
        XCTAssertTrue(assessment.hasUnobstructedCorner)
    }

    func testParkingAssessmentIsObstructedWhenBothBottomCornersAreBlocked() {
        let center = display(id: 1, x: 0, y: 0)
        let displays = [
            center,
            display(id: 2, x: -1000, y: 0),
            display(id: 3, x: 1000, y: 0)
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: center,
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomRight)
        XCTAssertFalse(assessment.hasUnobstructedCorner)
    }

    func testParkingAssessmentUsesTheSideWithLessAbsoluteOverlap() {
        let center = display(id: 1, x: 0, y: 0, width: 2000, height: 1000)
        let displays = [
            center,
            display(id: 2, x: -1000, y: 0, width: 1000, height: 1000),
            display(id: 3, x: 2000, y: 0, width: 3000, height: 1000)
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: center,
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomLeft)
        XCTAssertFalse(assessment.hasUnobstructedCorner)
    }

    func testParkingAssessmentHandlesOffsetThreeDisplayLayout() {
        let upperLeft = display(id: 1, x: 0, y: 0, width: 2000, height: 1000)
        let lowerLeft = display(id: 2, x: 250, y: 1000, width: 1500, height: 1000)
        let right = display(id: 3, x: 2000, y: -300, width: 1000, height: 1800)
        let displays = [upperLeft, lowerLeft, right]

        XCTAssertEqual(
            WindowParkingPointProvider.assessment(for: upperLeft, among: displays).corner,
            .bottomLeft
        )
        XCTAssertEqual(
            WindowParkingPointProvider.assessment(for: lowerLeft, among: displays).corner,
            .bottomRight
        )
        XCTAssertEqual(
            WindowParkingPointProvider.assessment(for: right, among: displays).corner,
            .bottomRight
        )
    }

    func testParkingAssessmentUsesRightTieBreakForAlignedVerticalDisplays() {
        let upper = display(id: 1, x: 0, y: 0)
        let lower = display(id: 2, x: 0, y: 1000)
        let displays = [upper, lower]

        let assessment = WindowParkingPointProvider.assessment(
            for: upper,
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomRight)
        XCTAssertFalse(assessment.hasUnobstructedCorner)
    }

    func testParkingAssessmentAnchorsCandidatesToTheVisibleFrame() {
        let center = DisplaySnapshot(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main
        )
        let displays = [
            center,
            display(id: 2, x: -1000, y: 800, width: 1000, height: 100),
            display(id: 3, x: 1000, y: 990, width: 1000, height: 10)
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: center,
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomRight)
        XCTAssertFalse(assessment.hasUnobstructedCorner)
    }

    func testParkingAssessmentTreatsEdgeOnlyContactAsUnobstructed() {
        let center = display(id: 1, x: 0, y: 0)
        let displays = [
            center,
            display(id: 2, x: 1999, y: 999)
        ]

        let assessment = WindowParkingPointProvider.assessment(
            for: center,
            among: displays
        )

        XCTAssertEqual(assessment.corner, .bottomRight)
        XCTAssertTrue(assessment.hasUnobstructedCorner)
    }

    private func display(
        id: UInt32,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat = 1000,
        height: CGFloat = 1000
    ) -> DisplaySnapshot {
        DisplaySnapshot(
            id: id,
            frame: CGRect(x: x, y: y, width: width, height: height),
            role: id == 1 ? .main : .extended
        )
    }
}
