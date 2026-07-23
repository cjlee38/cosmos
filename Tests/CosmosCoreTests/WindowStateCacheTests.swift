@testable import CosmosCore
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

    func testPartialDiscoveryUpdatesAffectedWindowsAndCurrentStackOrder() {
        let cache = WindowStateCache()
        _ = cache.replace(
            windows: [
                .window(id: 100, title: "unchanged"),
                .window(id: 200, title: "old")
            ],
            focusedWindowID: 100,
            displayTopology: .empty
        )

        let diff = cache.apply(
            WindowDiscoverySnapshot(
                scope: .windows([200]),
                windows: [.window(id: 200, title: "updated")],
                focusedWindowID: 200,
                frontToBackWindowIDs: [200, 100]
            ),
            displayTopology: .empty
        )

        XCTAssertEqual(diff, .empty)
        XCTAssertEqual(cache.windows.map(\.id), [200, 100])
        XCTAssertEqual(cache.snapshot(for: 100)?.title, "unchanged")
        XCTAssertEqual(cache.snapshot(for: 200)?.title, "updated")
        XCTAssertEqual(cache.focusedWindowID, 200)
    }

    func testRecoveryDiscoveryPreservesWindowsMissingFromTheSnapshot() {
        let cache = WindowStateCache()
        _ = cache.replace(
            windows: [
                .window(id: 100, title: "visible"),
                .window(id: 200, title: "temporarily missing")
            ],
            focusedWindowID: 100,
            displayTopology: .empty
        )

        let diff = cache.apply(
            WindowDiscoverySnapshot(
                scope: .full,
                windows: [.window(id: 100, title: "updated")],
                focusedWindowID: 100,
                frontToBackWindowIDs: [100],
                unresolvedWindowIDs: [200]
            ),
            displayTopology: .empty
        )

        XCTAssertEqual(diff, .empty)
        XCTAssertEqual(cache.windows.map(\.id), [100, 200])
        XCTAssertEqual(cache.snapshot(for: 100)?.title, "updated")
        XCTAssertEqual(cache.snapshot(for: 200)?.title, "temporarily missing")

        let authoritativeDiff = cache.apply(
            WindowDiscoverySnapshot(
                scope: .full,
                windows: [.window(id: 100, title: "updated again")],
                focusedWindowID: 100,
                frontToBackWindowIDs: [100]
            ),
            displayTopology: .empty
        )

        XCTAssertEqual(authoritativeDiff, WindowSetDiff(removed: [200]))
        XCTAssertEqual(cache.windows.map(\.id), [100])
    }
}
