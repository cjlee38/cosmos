import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceDisplayArrangementTests: XCTestCase {
    func testSpaceDragPayloadRoundTripsSpaceID() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cosmos.space-test"))
        pasteboard.clearContents()
        pasteboard.writeObjects([SpaceDragPayload.pasteboardItem(for: "A")])

        XCTAssertEqual(SpaceDragPayload.spaceID(from: pasteboard), "A")
    }

    func testDisplayArrangementHitTestsTheSpaceUnderThePointer() throws {
        let display = SpaceSettingsDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            spaceIDs: ["1", "Y"]
        )
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [display],
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let one = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        let letterY = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.Y"
        })
        let onePoint = NSPoint(x: one.frame.midX, y: one.frame.midY)
        let letterYPoint = NSPoint(x: letterY.frame.midX, y: letterY.frame.midY)

        XCTAssertTrue(one.hitTest(onePoint) === one)
        XCTAssertTrue(letterY.hitTest(letterYPoint) === letterY)
        XCTAssertNil(one.hitTest(letterYPoint))
        XCTAssertNil(letterY.hitTest(onePoint))
    }

    func testDisplayArrangementShowsOverflowInsteadOfDroppingSpaceIDs() throws {
        let display = SpaceSettingsDisplay(
            id: 1,
            name: "Small Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            spaceIDs: SpaceID.allCases
        )
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 260, height: 140))
        arrangement.apply(
            [display],
            selectedDisplayID: 1,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let overflow = try XCTUnwrap(
            descendants(of: arrangement)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space-overflow" }
        )
        XCTAssertFalse(overflow.isHidden)
        XCTAssertTrue(overflow.title.hasPrefix("+"))
    }

    func testDisplayArrangementShowsParkingWarningForObstructedDisplay() throws {
        let obstructed = SpaceSettingsDisplay(
            id: 1,
            name: "Center Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            spaceIDs: ["1"],
            hasUnobstructedParkingCorner: false
        )
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [obstructed],
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )

        let warning = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display-parking-warning.1"
        })

        XCTAssertFalse(warning.isHidden)
        XCTAssertEqual(
            warning.toolTip,
            "No unobstructed parking corner is available. "
                + "Hidden windows may remain visible and clickable on another display. "
                + "Rearrange the displays in System Settings."
        )
    }

    func testDisplayArrangementHidesParkingWarningForSafeDisplays() throws {
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [settingsSnapshot().displays[0]],
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )

        let warning = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display-parking-warning.1"
        })

        XCTAssertTrue(warning.isHidden)
        XCTAssertNil(warning.toolTip)
    }

    func testDisplayArrangementPreservesMinimumCardSizeAndExpandsForVerticalLayouts() throws {
        let displays = [
            SpaceSettingsDisplay(
                id: 1,
                name: "Top",
                frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
                role: .main,
                monitorSlot: 1,
                spaceIDs: ["1"]
            ),
            SpaceSettingsDisplay(
                id: 2,
                name: "Bottom",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                role: .extended,
                monitorSlot: 2,
                spaceIDs: ["2"]
            )
        ]
        let arrangement = SpaceDisplayArrangementView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 210)
        )
        arrangement.apply(
            displays,
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let cards = try displays.map { display in
            try XCTUnwrap(descendants(of: arrangement).first {
                $0.accessibilityIdentifier() == "cosmos.settings.display.\(display.monitorSlot)"
            })
        }
        XCTAssertTrue(cards.allSatisfy { $0.frame.width >= 210 })
        XCTAssertTrue(cards.allSatisfy { $0.frame.height >= 130 })
        XCTAssertGreaterThan(arrangement.intrinsicContentSize.height, 210)
    }

    func testDisplayArrangementScrollsInsteadOfShrinkingWideLayouts() throws {
        let displays: [SpaceSettingsDisplay] = (0 ..< 3).map { index in
            let slot = index + 1
            let role: DisplayRole = index == 0 ? .main : .extended
            let frame = CGRect(x: CGFloat(index) * 1440, y: 0, width: 1440, height: 900)
            return SpaceSettingsDisplay(
                id: DisplayID(slot),
                name: "Display \(slot)",
                frame: frame,
                role: role,
                monitorSlot: slot,
                spaceIDs: [SpaceID.allCases[slot]]
            )
        }
        let arrangement = SpaceDisplayArrangementView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 210)
        )
        arrangement.apply(
            displays,
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(descendants(of: arrangement).compactMap { $0 as? NSScrollView }.first)
        let documentView = try XCTUnwrap(scrollView.documentView)

        XCTAssertGreaterThan(documentView.frame.width, scrollView.contentSize.width)
        XCTAssertTrue(displays.allSatisfy { display in
            descendants(of: arrangement).first {
                $0.accessibilityIdentifier() == "cosmos.settings.display.\(display.monitorSlot)"
            }.map { $0.frame.width >= 210 } ?? false
        })
    }
}
