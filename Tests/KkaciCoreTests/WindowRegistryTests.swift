@testable import KkaciCore
import XCTest

final class WindowRegistryTests: XCTestCase {
    func testStackIndexOrdersTwoKnownWindowsFrontToBack() {
        let front = WindowSnapshot.window(id: 10, title: "", appName: "Zed")
        let back = WindowSnapshot.window(id: 20, title: "", appName: "Arc")

        XCTAssertTrue(WindowRegistry.sortByFrontToBackOrder(
            front,
            back,
            frontToBackIndex: [10: 2, 20: 8]
        ))
    }

    func testKnownStackIndexPrecedesAWindowMissingFromTheStack() {
        let known = WindowSnapshot.window(id: 10, title: "", appName: "Zed")
        let missing = WindowSnapshot.window(id: 20, title: "", appName: "Arc")

        XCTAssertTrue(WindowRegistry.sortByFrontToBackOrder(
            known,
            missing,
            frontToBackIndex: [10: 2]
        ))
        XCTAssertFalse(WindowRegistry.sortByFrontToBackOrder(
            missing,
            known,
            frontToBackIndex: [10: 2]
        ))
    }

    func testEqualStackIndexUsesWindowIDAsTieBreaker() {
        let lowerID = WindowSnapshot.window(id: 10, title: "", appName: "Zed")
        let higherID = WindowSnapshot.window(id: 20, title: "", appName: "Arc")

        XCTAssertTrue(WindowRegistry.sortByFrontToBackOrder(
            lowerID,
            higherID,
            frontToBackIndex: [10: 2, 20: 2]
        ))
    }

    func testMissingStackIndexesUseStableApplicationAndWindowOrder() {
        let arc = WindowSnapshot.window(id: 20, title: "", appName: "Arc")
        let zedLowerID = WindowSnapshot.window(id: 10, title: "", appName: "Zed")
        let zedHigherID = WindowSnapshot.window(id: 30, title: "", appName: "Zed")

        XCTAssertTrue(WindowRegistry.sortByFrontToBackOrder(
            arc,
            zedLowerID,
            frontToBackIndex: [:]
        ))
        XCTAssertTrue(WindowRegistry.sortByFrontToBackOrder(
            zedLowerID,
            zedHigherID,
            frontToBackIndex: [:]
        ))
    }
}
