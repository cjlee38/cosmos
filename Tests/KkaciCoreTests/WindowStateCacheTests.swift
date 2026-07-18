@testable import KkaciCore
import XCTest

final class WindowStateCacheTests: XCTestCase {
    func testFirstReplaceEstablishesBaselineWithoutReportingRemovedWindows() {
        let cache = WindowStateCache()
        let windows = [
            WindowSnapshot.window(id: 200, title: "second"),
            WindowSnapshot.window(id: 100, title: "first")
        ]

        let diff = cache.replace(
            windows: windows,
            focusedWindowID: 200,
            displayTopology: .empty
        )

        XCTAssertEqual(diff, .empty)
        XCTAssertEqual(cache.windows.map(\.id), [200, 100])
        XCTAssertEqual(cache.focusedWindowID, 200)
    }

    func testSubsequentReplaceReportsRemovedWindowsAndStoresLatestSnapshot() {
        let cache = WindowStateCache()
        _ = cache.replace(
            windows: [
                .window(id: 300, title: "removed"),
                .window(id: 100, title: "kept")
            ],
            focusedWindowID: 300,
            displayTopology: .empty
        )

        let diff = cache.replace(
            windows: [
                .window(id: 200, title: "added"),
                .window(id: 100, title: "kept")
            ],
            focusedWindowID: 100,
            displayTopology: .empty
        )

        XCTAssertEqual(diff, WindowSetDiff(removed: [300]))
        XCTAssertEqual(cache.windows.map(\.id), [200, 100])
        XCTAssertEqual(cache.focusedWindowID, 100)
    }
}
