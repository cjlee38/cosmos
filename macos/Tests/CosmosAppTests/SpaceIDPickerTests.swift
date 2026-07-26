import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceIDPickerTests: XCTestCase {
    func testSpaceIDPickerDistinguishesConfiguredAndAvailableSelections() throws {
        let picker = SpaceIDPickerView()
        picker.apply(
            monitorSlotBySpaceID: ["1": 1, "A": 1, "C": 2],
            selectedMonitorSlot: 1
        )
        var availableSelection: SpaceID?
        var configuredSelection: SpaceID?
        var removalSelection: SpaceID?
        picker.onSpaceSelected = { availableSelection = $0 }
        picker.onConfiguredSpaceSelected = { configuredSelection = $0 }
        picker.onSpaceRemovalRequested = { removalSelection = $0 }
        var deleteMode = false
        picker.onDeleteModeChanged = { deleteMode = $0 }
        let buttons = descendants(of: picker).compactMap { $0 as? SpaceIDKeyButton }
        let zero = try XCTUnwrap(buttons.first { $0.spaceID == "0" })
        let one = try XCTUnwrap(buttons.first { $0.spaceID == "1" })
        let letterA = try XCTUnwrap(buttons.first { $0.spaceID == "A" })
        let letterB = try XCTUnwrap(buttons.first { $0.spaceID == "B" })
        let letterC = try XCTUnwrap(buttons.first { $0.spaceID == "C" })

        XCTAssertTrue(zero.isEnabled)
        XCTAssertTrue(one.isEnabled)
        XCTAssertTrue(letterA.isEnabled)
        XCTAssertFalse(letterC.isEnabled)
        XCTAssertEqual(letterC.toolTip, "Assigned to Display 2")

        letterA.performClick(nil)
        zero.performClick(nil)
        letterB.performClick(nil)

        XCTAssertEqual(configuredSelection, "A")
        XCTAssertEqual(availableSelection, "B")

        let deleteButton = try XCTUnwrap(
            descendants(of: picker)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space.delete-mode" }
        )
        deleteButton.performClick(nil)
        XCTAssertTrue(deleteMode)

        picker.apply(
            monitorSlotBySpaceID: ["1": 1, "A": 1, "C": 2],
            selectedMonitorSlot: 1,
            isDeleteMode: deleteMode
        )
        XCTAssertFalse(zero.isEnabled)
        XCTAssertTrue(one.isEnabled)
        XCTAssertFalse(letterC.isEnabled)
        one.performClick(nil)

        XCTAssertEqual(removalSelection, "1")
    }

    func testSpaceIDPickerCentersTheKeyboard() {
        let picker = SpaceIDPickerView()
        picker.frame = NSRect(x: 0, y: 0, width: 520, height: 184)
        picker.layoutSubtreeIfNeeded()

        let buttons = descendants(of: picker).compactMap { $0 as? SpaceIDKeyButton }
        let frames = buttons.map { picker.convert($0.bounds, from: $0) }
        let keyboardFrame = frames.reduce(NSRect.null) { $0.union($1) }

        XCTAssertEqual(keyboardFrame.midX, picker.bounds.midX, accuracy: 1)

        let deleteButton = descendants(of: picker)
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "cosmos.settings.space.delete-mode" }
        XCTAssertEqual(deleteButton?.frame.width, 32)
        XCTAssertEqual(deleteButton?.frame.height, 32)
        XCTAssertEqual(deleteButton?.frame.maxX, picker.bounds.maxX)
        XCTAssertEqual(deleteButton?.frame.minY, picker.bounds.minY)
    }
}
