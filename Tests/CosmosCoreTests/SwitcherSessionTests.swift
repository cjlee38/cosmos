@testable import CosmosCore
import XCTest

final class SwitcherSessionTests: SpaceControllerTestCase {
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

    func testNonWrappingStepsStopAtTheEnds() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: 1,
            direction: .forward
        ))

        session.step(.forward, wraps: false)
        session.step(.forward, wraps: false)
        XCTAssertEqual(session.selectedItem, 3)

        session.step(.backward, wraps: false)
        session.step(.backward, wraps: false)
        session.step(.backward, wraps: false)
        XCTAssertEqual(session.selectedItem, 1)
    }

    func testHorizontalArrowKeysMoveOneItemAtATime() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3, 4, 5, 6],
            currentItem: nil,
            direction: .backward
        ))

        session.move(.right)
        session.move(.right)
        session.move(.right)
        XCTAssertEqual(session.selectedItem, 4)
        session.move(.left)
        XCTAssertEqual(session.selectedItem, 3)
    }

    func testArrowKeysStopAtListBoundaries() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: nil,
            direction: .backward
        ))

        session.move(.left)
        XCTAssertEqual(session.selectedItem, 1)

        for _ in 0 ..< 10 {
            session.move(.right)
        }
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

    func testReconcilePreservesSelectedItemAcrossReorderingAndAdditions() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: 1,
            direction: .forward
        ))

        XCTAssertTrue(session.reconcile(with: [4, 3, 2, 1]))

        XCTAssertEqual(session.items, [4, 3, 2, 1])
        XCTAssertEqual(session.selectedItem, 2)
    }

    func testReconcilePreservesSelectionWhenAnotherItemIsRemoved() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3, 4],
            currentItem: 2,
            direction: .forward
        ))

        XCTAssertTrue(session.reconcile(with: [1, 3, 4]))

        XCTAssertEqual(session.selectedItem, 3)
    }

    func testReconcileSelectedRemovalKeepsItsOrdinalWhenPossible() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3, 4],
            currentItem: 1,
            direction: .forward
        ))

        XCTAssertTrue(session.reconcile(with: [1, 3, 4]))

        XCTAssertEqual(session.selectedItem, 3)
    }

    func testReconcileSelectedLastItemUsesNewLastItem() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1, 2, 3],
            currentItem: 2,
            direction: .forward
        ))

        XCTAssertTrue(session.reconcile(with: [1, 2]))

        XCTAssertEqual(session.selectedItem, 2)
    }

    func testReconcileEmptyItemsEndsTheSession() throws {
        var session = try XCTUnwrap(SwitcherSession(
            items: [1],
            currentItem: nil,
            direction: .forward
        ))

        XCTAssertFalse(session.reconcile(with: []))
    }

    func testEmptyItemsDoNotCreateASession() {
        XCTAssertNil(SwitcherSession<Int>(
            items: [],
            currentItem: nil,
            direction: .forward
        ))
    }

    func testSpaceWindowsKeepCurrentMacOSZOrderAndExcludeMinimizedWindows() throws {
        let windowSystem = FakeWindowSystem(windows: [])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        windowSystem.windows = [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two"),
            .window(id: 300, title: "Three", isMinimized: true)
        ]
        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.windows(in: "1").map(\.id), [100, 200])

        windowSystem.windows = [
            .window(id: 200, title: "Two"),
            .window(id: 100, title: "One"),
            .window(id: 300, title: "Three", isMinimized: true)
        ]
        _ = try controller.handleWindowSetChanged()

        XCTAssertEqual(controller.windows(in: "1").map(\.id), [200, 100])
    }

    func testRapidWindowSwitcherSessionsFollowCurrentMacOSZOrder() throws {
        let windowSystem = FakeWindowSystem(windows: [])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        windowSystem.windows = [
            .window(id: 1, title: "One"),
            .window(id: 2, title: "Two"),
            .window(id: 3, title: "Three")
        ]
        _ = try controller.handleWindowSetChanged()

        let firstOrder = controller.windows(in: "1").map(\.id)
        let firstSession = try XCTUnwrap(SwitcherSession(
            items: firstOrder,
            currentItem: firstOrder.first,
            direction: .forward
        ))
        XCTAssertEqual(firstSession.selectedItem, 2)
        try controller.focusWindow(firstSession.selectedItem)

        windowSystem.windows = [
            .window(id: 2, title: "Two"),
            .window(id: 1, title: "One"),
            .window(id: 3, title: "Three")
        ]
        _ = try controller.handleWindowSetChanged()

        let secondOrder = controller.windows(in: "1").map(\.id)
        let secondSession = try XCTUnwrap(SwitcherSession(
            items: secondOrder,
            currentItem: secondOrder.first,
            direction: .forward
        ))
        XCTAssertEqual(secondSession.selectedItem, 1)
    }
}
