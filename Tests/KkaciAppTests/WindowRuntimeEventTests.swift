import ApplicationServices
@testable import KkaciApp
import KkaciCore
import XCTest

final class WindowRuntimeEventTests: XCTestCase {
    func testResizeRequiresLayoutSyncAndThumbnailCapture() {
        let kinds = WindowRuntimeEventKind.kinds(
            forAXNotification: kAXWindowResizedNotification as String
        )
        let batch = WindowRuntimeEventBatch(events: Set(kinds.map { kind in
            WindowRuntimeEvent(kind: kind, windowID: 100)
        }))

        XCTAssertEqual(kinds, [.layoutChanged, .thumbnailChanged])
        XCTAssertTrue(batch.containsLayoutChange)
        XCTAssertEqual(batch.windowIDsNeedingCapture, [100])
    }

    func testDisplayChangeIsRecognizedAsTopologyAndFullThumbnailChange() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .displayChanged, windowID: nil)
        ])

        XCTAssertTrue(batch.containsDisplayChange)
        XCTAssertTrue(batch.needsFullThumbnailRefresh)
    }

    func testEventKindsPreserveDistinctFocusLayoutAndThumbnailSemantics() {
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXFocusedWindowChangedNotification as String),
            [.focusChanged]
        )
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXWindowMovedNotification as String),
            [.layoutChanged]
        )
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXTitleChangedNotification as String),
            [.thumbnailChanged]
        )
    }

    func testFocusSuppressionSurvivesUnrelatedEventsAndIsConsumedOnce() {
        var suppression = FocusSyncSuppression()
        suppression.suppress(100)

        XCTAssertFalse(suppression.shouldFollow(requested: false, focusedWindowID: 100))
        XCTAssertFalse(suppression.shouldFollow(requested: true, focusedWindowID: 100))
        XCTAssertTrue(suppression.shouldFollow(requested: true, focusedWindowID: 100))
    }

    func testFocusSuppressionAllowsAndConsumesADifferentFocusedWindow() {
        var suppression = FocusSyncSuppression()
        suppression.suppress(100)

        XCTAssertTrue(suppression.shouldFollow(requested: true, focusedWindowID: 200))
        XCTAssertTrue(suppression.shouldFollow(requested: true, focusedWindowID: 100))
    }

    func testSuccessfulWindowEventAlwaysRefreshesSwitcherContent() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "Window")
        ])
        var switcherRefreshCount = 0
        var surfaceRefreshCount = 0
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {
                switcherRefreshCount += 1
            },
            refreshSurfaces: {
                surfaceRefreshCount += 1
            }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        ]))

        XCTAssertEqual(switcherRefreshCount, 1)
        XCTAssertEqual(surfaceRefreshCount, 1)
    }

    func testFocusEventSwitchesToTheFocusedWindowsWorkspace() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindowIDValue = 200
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .focusChanged, windowID: 200)
        ]))

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testLayoutEventForHiddenFocusedWindowDoesNotSwitchWorkspace() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindowIDValue = 200
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 200)
        ]))

        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertTrue(controller.isHiddenByWorkspace(200))
    }

    func testDisplayEventRefreshesEveryLiveWindowThumbnail() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        let captured = expectation(description: "all window thumbnails captured")
        captured.expectedFulfillmentCount = 2
        var capturedIDs: Set<WindowID> = []
        let previewService = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { windowID in
                capturedIDs.insert(windowID)
                captured.fulfill()
                return nil
            }
        )
        let handler = makeHandler(controller: controller, previewService: previewService)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .displayChanged, windowID: nil)
        ]))

        wait(for: [captured], timeout: 1)
        XCTAssertEqual(capturedIDs, [100, 200])
    }

    func testFailedWindowSyncDoesNotRefreshSwitcherOrStatusSurfaces() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try controller.assignWindow(200, to: "2")
        windowSystem.focusedWindowIDValue = 200
        windowSystem.frameWriteFailures.insert(200)
        var switcherRefreshCount = 0
        var surfaceRefreshCount = 0
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: { switcherRefreshCount += 1 },
            refreshSurfaces: { surfaceRefreshCount += 1 }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .focusChanged, windowID: 200)
        ]))

        XCTAssertEqual(controller.currentWorkspace, "1")
        XCTAssertEqual(switcherRefreshCount, 0)
        XCTAssertEqual(surfaceRefreshCount, 0)
    }

    private func makeHandler(
        controller: WorkspaceController,
        previewService: SwitcherPreviewService? = nil
    ) -> WindowRuntimeEventHandler {
        WindowRuntimeEventHandler(
            controller: controller,
            previewService: previewService ?? makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshSurfaces: {}
        )
    }
}
