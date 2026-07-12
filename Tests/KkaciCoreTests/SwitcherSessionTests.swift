@testable import KkaciCore
import XCTest

final class SwitcherSessionTests: WorkspaceControllerTestCase {
    func testStartsFromTheItemAfterCurrentSelection() throws {
        let session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: 1,
            direction: .forward
        ))

        XCTAssertEqual(session.selectedItem, 2)
    }

    func testBackwardSelectionWrapsFromFirstToLast() throws {
        let session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: 1,
            direction: .backward
        ))

        XCTAssertEqual(session.selectedItem, 3)
    }

    func testRepeatedStepsWrapInBothDirections() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: 1,
            direction: .forward
        ))

        session.step(.forward)
        XCTAssertEqual(session.selectedItem, 3)
        session.step(.forward)
        XCTAssertEqual(session.selectedItem, 1)
        session.step(.backward)
        XCTAssertEqual(session.selectedItem, 3)
    }

    func testMouseSelectionChangesTheSameSessionState() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: ["1", "2", "3"],
            currentItem: "1",
            direction: .forward
        ))

        XCTAssertTrue(session.select("3"))
        XCTAssertEqual(session.selectedItem, "3")
        XCTAssertFalse(session.select("missing"))
        XCTAssertEqual(session.selectedItem, "3")
    }

    func testEmptyItemsDoNotCreateASession() {
        XCTAssertNil(SwitcherSession<Int>(
            items: [],
            currentItem: nil,
            direction: .forward
        ))
    }

    func testRapidWindowSwitcherSessionsAlternateBetweenTwoMostRecentWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 1, title: "One"),
            .window(id: 2, title: "Two"),
            .window(id: 3, title: "Three")
        ])
        let controller = makeController(windowSystem)

        _ = controller.listWindows()
        try controller.assignWindow(3, to: "1")
        try controller.assignWindow(2, to: "1")
        try controller.assignWindow(1, to: "1")

        let firstOrder = controller.windowIDsByMostRecentFocus(in: "1")
        let firstSession = try XCTUnwrap(SwitcherSession(
            items: firstOrder,
            currentItem: firstOrder.first,
            direction: .forward
        ))
        XCTAssertEqual(firstSession.selectedItem, 2)
        try controller.focusWindow(firstSession.selectedItem)

        let secondOrder = controller.windowIDsByMostRecentFocus(in: "1")
        let secondSession = try XCTUnwrap(SwitcherSession(
            items: secondOrder,
            currentItem: secondOrder.first,
            direction: .forward
        ))
        XCTAssertEqual(secondSession.selectedItem, 1)
    }
}
