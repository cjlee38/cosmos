import CoreGraphics
@testable import CosmosCore
import XCTest

final class SpaceRuntimeSynchronizerTests: SpaceControllerTestCase {
    func testInitialSyncAssignsVisibleWindowsToCurrentSpace() throws {
        let runtime = makeRuntime(windows: [.window(id: 100, title: "existing")])
        var state = SpaceState()

        let sync = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(sync.autoAssigned.map(\.0), [100])
        XCTAssertEqual(sync.autoAssigned.map(\.1), ["1"])
        XCTAssertEqual(state.membership(for: 100), "1")
    }

    func testNewWindowsAreAutoAssignedToCurrentSpace() throws {
        let runtime = makeRuntime(windows: [.window(id: 100, title: "existing")])
        var state = SpaceState()
        _ = try runtime.synchronizer.synchronize(state: &state)
        state.activate("3")
        runtime.windowSystem.windows.append(.window(id: 200, title: "new"))

        let sync = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(
            sync.membershipChanges,
            [SpaceMembershipChange(windowID: 200, previousSpace: nil, space: "3")]
        )
        XCTAssertEqual(state.membership(for: 200), "3")
    }

    func testPreviouslyMinimizedWindowIsAssignedWhenItBecomesVisible() throws {
        let runtime = makeRuntime(windows: [.window(id: 100, title: "Window", isMinimized: true)])
        var state = SpaceState()
        _ = try runtime.synchronizer.synchronize(state: &state)
        runtime.windowSystem.windows = [.window(id: 100, title: "Window")]

        let sync = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(sync.autoAssigned.map(\.0), [100])
        XCTAssertEqual(state.membership(for: 100), "1")
    }

    func testNewWindowsUseTheVisibleSpaceOnTheirMonitorSlot() throws {
        let runtime = makeRuntime(
            windows: [
                .window(id: 100, title: "main", frame: .frame(x: 100, y: 100)),
                .window(id: 200, title: "secondary", frame: .frame(x: 1100, y: 100))
            ],
            displayProvider: twoDisplayProvider()
        )
        var state = SpaceState(
            config: CosmosConfig(spaces: spaceConfigs(["1", "2"], displays: ["2": 2]))
        )

        _ = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(state.membership(for: 100), "1")
        XCTAssertEqual(state.membership(for: 200), "2")
    }

    func testRemovedWindowsArePrunedFromMembershipAndHiddenState() throws {
        let runtime = makeRuntime(windows: [
            .window(id: 100, title: "first"),
            .window(id: 200, title: "second")
        ])
        var state = SpaceState()
        _ = try runtime.synchronizer.synchronize(state: &state)
        state.assign(200, to: "2")
        state.storeHiddenFrameIfNeeded(.frame(x: 20, y: 20), for: 200)
        runtime.windowSystem.windows = [.window(id: 100, title: "first")]

        let sync = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(sync.removed, [200])
        XCTAssertNil(state.membership(for: 200))
        XCTAssertFalse(state.isHidden(200))
    }

    func testVisibleWindowMonitorChangeReportsPreviousAndCurrentSpace() throws {
        let runtime = makeRuntime(
            windows: [.window(id: 100, title: "Window", frame: .frame(x: 100, y: 100))],
            displayProvider: twoDisplayProvider()
        )
        var state = SpaceState(
            config: CosmosConfig(spaces: spaceConfigs(["1", "A"], displays: ["A": 2]))
        )
        _ = try runtime.synchronizer.synchronize(state: &state)
        runtime.windowSystem.frames[100] = .frame(x: 1100, y: 100)

        let sync = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(
            sync.membershipChanges,
            [SpaceMembershipChange(windowID: 100, previousSpace: "1", space: "A")]
        )
    }

    func testRefreshFailurePreservesCachedWindowsAndSpaceState() throws {
        let runtime = makeRuntime(windows: [
            .window(id: 100, title: "first"),
            .window(id: 200, title: "second")
        ])
        var state = SpaceState()
        _ = try runtime.synchronizer.synchronize(state: &state)
        state.assign(200, to: "2")
        state.storeHiddenFrameIfNeeded(.frame(x: 20, y: 20), for: 200)
        runtime.windowSystem.refreshError = FakeWindowSystemError.refresh

        XCTAssertThrowsError(try runtime.synchronizer.synchronize(state: &state))

        XCTAssertEqual(runtime.windowCache.windows.map(\.id), [100, 200])
        XCTAssertEqual(state.membership(for: 100), "1")
        XCTAssertEqual(state.membership(for: 200), "2")
        XCTAssertTrue(state.isHidden(200))
    }

    func testSyncRecoversAfterARefreshFailure() throws {
        let runtime = makeRuntime(windows: [.window(id: 100, title: "first")])
        var state = SpaceState()
        _ = try runtime.synchronizer.synchronize(state: &state)
        runtime.windowSystem.refreshError = FakeWindowSystemError.refresh
        XCTAssertThrowsError(try runtime.synchronizer.synchronize(state: &state))

        runtime.windowSystem.refreshError = nil
        runtime.windowSystem.windows.append(.window(id: 200, title: "second"))
        let sync = try runtime.synchronizer.synchronize(state: &state)

        XCTAssertEqual(sync.autoAssigned.map(\.0), [200])
        XCTAssertEqual(runtime.windowCache.windows.map(\.id), [100, 200])
    }

    func testDisplayQueryFailurePreservesCachedWindowsAndSpaceState() throws {
        let displayProvider = FakeDisplayProvider()
        let runtime = makeRuntime(
            windows: [
                .window(id: 100, title: "first"),
                .window(id: 200, title: "second")
            ],
            displayProvider: displayProvider
        )
        var state = SpaceState()
        _ = try runtime.synchronizer.synchronize(state: &state)
        state.assign(200, to: "2")
        state.storeHiddenFrameIfNeeded(.frame(x: 20, y: 20), for: 200)
        displayProvider.displayError = FakeWindowSystemError.refresh

        XCTAssertThrowsError(try runtime.synchronizer.synchronize(state: &state))

        XCTAssertEqual(runtime.windowCache.windows.map(\.id), [100, 200])
        XCTAssertEqual(state.membership(for: 100), "1")
        XCTAssertEqual(state.membership(for: 200), "2")
        XCTAssertTrue(state.isHidden(200))
    }
}

private extension SpaceRuntimeSynchronizerTests {
    struct Runtime {
        let windowSystem: FakeWindowSystem
        let windowCache: WindowStateCache
        let synchronizer: SpaceRuntimeSynchronizer
    }

    func makeRuntime(
        windows: [WindowSnapshot],
        displayProvider: FakeDisplayProvider = FakeDisplayProvider()
    ) -> Runtime {
        let windowSystem = FakeWindowSystem(windows: windows)
        let windowCache = WindowStateCache()
        let monitorSlotResolver = MonitorSlotResolver(displayProvider: displayProvider)
        return Runtime(
            windowSystem: windowSystem,
            windowCache: windowCache,
            synchronizer: SpaceRuntimeSynchronizer(
                windowSystem: windowSystem,
                windowCache: windowCache,
                recordRepository: HiddenWindowRecordRepository(store: nil),
                monitorSlotResolver: monitorSlotResolver,
                hidePointProvider: displayProvider
            )
        )
    }
}
