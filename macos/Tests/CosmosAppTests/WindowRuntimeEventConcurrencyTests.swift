import ApplicationServices
@testable import CosmosApp
import CosmosCore
import XCTest

final class WindowRuntimeEventConcurrencyTests: XCTestCase {
    func testWindowSetChangeMixedWithSessionResumeRemainsAuthoritative() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One")
        ])
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))

        XCTAssertEqual(windowSystem.discoveryModes.last, .normal)
    }

    func testSessionResumePreservesTemporarilyMissingHiddenWindow() throws {
        let visibleWindow = makeSwitcherTestWindow(id: 100, title: "Visible")
        let hiddenWindow = makeSwitcherTestWindow(id: 200, title: "Hidden")
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            visibleWindow,
            hiddenWindow
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.sessionActivityChanged(isActive: false)
        windowSystem.replaceWindows([visibleWindow])
        windowSystem.unresolvedWindowIDs = [200]
        handler.sessionActivityChanged(isActive: true)

        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenBySpace(200))
        XCTAssertEqual(windowSystem.discoveryModes.last, .sessionRecovery)

        windowSystem.replaceWindows([visibleWindow, hiddenWindow])
        windowSystem.unresolvedWindowIDs = []
        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))

        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenBySpace(200))
        XCTAssertEqual(windowSystem.discoveryModes.last, .normal)
    }

    func testDiscoveryStartedBeforeSessionSuspensionIsDiscarded() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One")
        ])
        windowSystem.resetDiscoveryRequests()
        windowSystem.resetDiscoveryModes()
        var scheduledDiscovery: [() -> Void] = []
        var switcherRefreshCount = 0
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: { switcherRefreshCount += 1 },
            refreshStatusSurfaces: {},
            scheduleDiscovery: { scheduledDiscovery.append($0) },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))
        handler.sessionActivityChanged(isActive: false)
        handler.sessionActivityChanged(isActive: true)

        XCTAssertEqual(scheduledDiscovery.count, 1)
        scheduledDiscovery.removeFirst()()
        XCTAssertEqual(switcherRefreshCount, 0)
        XCTAssertEqual(windowSystem.discoveryModes, [.normal])
        XCTAssertEqual(scheduledDiscovery.count, 1)

        scheduledDiscovery.removeFirst()()

        XCTAssertEqual(windowSystem.discoveryRequests.count, 2)
        XCTAssertEqual(windowSystem.discoveryModes, [.normal, .sessionRecovery])
        XCTAssertEqual(switcherRefreshCount, 1)
    }

    func testFailedWindowSyncDoesNotRefreshSwitcherOrStatusSurfaces() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindowIDValue = 200
        windowSystem.frameWriteFailures.insert(200)
        var switcherRefreshCount = 0
        var surfaceRefreshCount = 0
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: { switcherRefreshCount += 1 },
            refreshStatusSurfaces: { surfaceRefreshCount += 1 },
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .applicationActivated, windowID: nil)
        ]))

        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertEqual(switcherRefreshCount, 0)
        XCTAssertEqual(surfaceRefreshCount, 0)
    }

    func testEventsReceivedDuringDiscoveryAreCoalescedIntoOneFollowingDiscovery() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        let initialRefreshCount = windowSystem.refreshCount
        windowSystem.resetDiscoveryRequests()
        var scheduledDiscovery: [() -> Void] = []
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: { scheduledDiscovery.append($0) },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        ]))
        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 200)
        ]))
        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 200)
        ]))

        XCTAssertEqual(scheduledDiscovery.count, 1)
        scheduledDiscovery.removeFirst()()
        XCTAssertEqual(windowSystem.discoveryRequests, [[100]])
        XCTAssertEqual(scheduledDiscovery.count, 1)
        scheduledDiscovery.removeFirst()()
        XCTAssertTrue(scheduledDiscovery.isEmpty)
        XCTAssertEqual(windowSystem.discoveryRequests, [[100], [200]])
        XCTAssertEqual(windowSystem.refreshCount, initialRefreshCount + 2)
    }

    func testWindowSetEventRequestsFullDiscovery() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One")
        ])
        windowSystem.resetDiscoveryRequests()
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: 100)
        ]))

        XCTAssertEqual(windowSystem.discoveryRequests.count, 1)
        XCTAssertNil(windowSystem.discoveryRequests[0])
    }

    func testStaleDiscoveryIsRetriedBeforeUpdatingSurfaces() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One")
        ])
        let initialRefreshCount = windowSystem.refreshCount
        windowSystem.resetDiscoveryRequests()
        windowSystem.discoveryApplyResults = [false, true]
        var switcherRefreshCount = 0
        var surfaceRefreshCount = 0
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: { switcherRefreshCount += 1 },
            refreshStatusSurfaces: { surfaceRefreshCount += 1 },
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        ]))

        XCTAssertEqual(windowSystem.refreshCount, initialRefreshCount + 2)
        XCTAssertEqual(windowSystem.discoveryRequests, [[100], [100]])
        XCTAssertEqual(switcherRefreshCount, 1)
        XCTAssertEqual(surfaceRefreshCount, 1)
    }
}
