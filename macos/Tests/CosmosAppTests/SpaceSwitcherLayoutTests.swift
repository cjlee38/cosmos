import AppKit
@testable import CosmosApp
import XCTest

final class SpaceSwitcherLayoutTests: XCTestCase {
    func testSpaceOverviewCardsNeverExceedTheirGridCells() {
        let layout = SpaceOverviewLayout(
            groupCount: 36,
            availableFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            size: 0
        )

        XCTAssertGreaterThan(layout.cardSize.width, 0)
        XCTAssertGreaterThan(layout.cardSize.height, 0)
        for row in 0 ..< 6 {
            for column in 0 ..< 6 {
                let cell = layout.cellFrame(row: row, column: column)
                XCTAssertLessThanOrEqual(layout.cardSize.width, cell.width)
                XCTAssertLessThanOrEqual(layout.cardSize.height, cell.height)
            }
        }
    }

    func testSpaceOverviewContentFitsThreeCardsWithoutVerticalCellPadding() {
        let layout = SpaceOverviewLayout(
            groupCount: 3,
            availableFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            size: 0.5
        )

        let cell = layout.cellFrame(row: 0, column: 0)
        XCTAssertEqual(layout.cardSize.height, cell.height, accuracy: 1)
        XCTAssertEqual(layout.contentSize.height, layout.cardSize.height, accuracy: 1)
    }

    func testSpaceApplicationIconsUseAtMostSeventyPercentOfPreviewWidth() throws {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 200)
        let layout = SpaceApplicationIconLayout(bounds: bounds, applicationCount: 13)
        let frames = try layout.iconFrames + [XCTUnwrap(layout.overflowFrame)]
        let minimumX = try XCTUnwrap(frames.map(\.minX).min())
        let maximumX = try XCTUnwrap(frames.map(\.maxX).max())

        XCTAssertLessThanOrEqual(maximumX - minimumX, 280)
        XCTAssertEqual(Set(frames.map(\.minY)).count, 2)
    }

    func testSpaceApplicationIconsUseOneRowWhenTwoRowsDoNotFit() throws {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 24)
        let layout = SpaceApplicationIconLayout(bounds: bounds, applicationCount: 20)
        let frames = try layout.iconFrames + [XCTUnwrap(layout.overflowFrame)]

        XCTAssertEqual(Set(frames.map(\.minY)).count, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(frames.map(\.maxY).max()), bounds.maxY)
    }

    func testSpaceApplicationIconOverflowUsesAnIconSizedLayoutSlot() throws {
        let layout = SpaceApplicationIconLayout(
            bounds: NSRect(x: 0, y: 0, width: 400, height: 200),
            applicationCount: 20
        )
        let overflowFrame = try XCTUnwrap(layout.overflowFrame)

        XCTAssertGreaterThan(layout.overflowCount, 0)
        XCTAssertEqual(overflowFrame.width, try XCTUnwrap(layout.iconFrames.first).width)
        XCTAssertEqual(overflowFrame.height, try XCTUnwrap(layout.iconFrames.first).height)
    }

    func testSpaceApplicationIconGridIsVerticallyCentered() throws {
        let bounds = NSRect(x: 0, y: 0, width: 400, height: 200)
        let layout = SpaceApplicationIconLayout(bounds: bounds, applicationCount: 13)
        let frames = try layout.iconFrames + [XCTUnwrap(layout.overflowFrame)]
        let minimumY = try XCTUnwrap(frames.map(\.minY).min())
        let maximumY = try XCTUnwrap(frames.map(\.maxY).max())

        XCTAssertEqual((minimumY + maximumY) / 2, bounds.midY, accuracy: 0.001)
    }

    func testSpaceApplicationIconSizeScalesWithPreviewArea() throws {
        let small = SpaceApplicationIconLayout(
            bounds: NSRect(x: 0, y: 0, width: 300, height: 120),
            applicationCount: 2
        )
        let large = SpaceApplicationIconLayout(
            bounds: NSRect(x: 0, y: 0, width: 600, height: 240),
            applicationCount: 2
        )

        XCTAssertEqual(
            try XCTUnwrap(large.iconFrames.first).width,
            try XCTUnwrap(small.iconFrames.first).width * 2,
            accuracy: 0.001
        )
    }

    func testSpaceApplicationIconColumnCountDoesNotShrinkAsPreviewGrows() {
        let small = SpaceApplicationIconLayout(
            bounds: NSRect(x: 0, y: 0, width: 411, height: 232),
            applicationCount: 20
        )
        let large = SpaceApplicationIconLayout(
            bounds: NSRect(x: 0, y: 0, width: 779, height: 506),
            applicationCount: 20
        )

        XCTAssertGreaterThanOrEqual(large.columns, small.columns)
    }
}
