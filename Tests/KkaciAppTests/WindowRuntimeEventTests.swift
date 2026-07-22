import ApplicationServices
@testable import KkaciApp
import KkaciCore
import XCTest

final class WindowRuntimeEventTests: XCTestCase {
    func testEventBufferDeduplicatesEventsIntoOneDelivery() {
        let event = WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(event)
        buffer.append(event)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertFalse(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
        XCTAssertNil(buffer.takeDelivery())
    }

    func testEventBufferDefersDeliveryUntilWindowDragEnds() {
        let event = WindowRuntimeEvent(kind: .layoutChanged, windowID: 100)
        var buffer = WindowRuntimeEventBuffer()

        buffer.beginWindowDrag()
        buffer.append(event)

        XCTAssertFalse(buffer.reserveDelivery())
        buffer.endWindowDrag()
        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
    }

    func testEventBufferKeepsReservedEventsWhenDragStartsBeforeDelivery() {
        let event = WindowRuntimeEvent(kind: .layoutChanged, windowID: 100)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(event)
        XCTAssertTrue(buffer.reserveDelivery())
        buffer.beginWindowDrag()

        XCTAssertNil(buffer.takeDelivery())
        buffer.endWindowDrag()
        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
    }

    func testEventBufferDiscardsPendingAndIncomingEventsWhileSessionIsInactive() {
        let pending = WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        let inactive = WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(pending)
        XCTAssertTrue(buffer.reserveDelivery())
        buffer.suspend()
        buffer.append(inactive)

        XCTAssertNil(buffer.takeDelivery())
        XCTAssertTrue(buffer.events.isEmpty)
    }

    func testEventBufferDeliversFreshSyncAfterSessionBecomesActive() {
        let freshSync = WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.suspend()
        buffer.resume()
        buffer.append(freshSync)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [freshSync])
    }

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

    func testApplicationActivationAndAXFocusChangeRemainDistinct() {
        let activation = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .applicationActivated, windowID: nil)
        ])
        let axFocus = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ])

        XCTAssertTrue(activation.containsApplicationActivation)
        XCTAssertTrue(activation.containsFocusChange)
        XCTAssertFalse(axFocus.containsApplicationActivation)
        XCTAssertTrue(axFocus.containsFocusChange)
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
            refreshStatusSurfaces: {
                surfaceRefreshCount += 1
            }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        ]))

        XCTAssertEqual(switcherRefreshCount, 1)
        XCTAssertEqual(surfaceRefreshCount, 1)
    }

    func testApplicationActivationSwitchesToTheFocusedWindowsWorkspace() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindowIDValue = 200
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .applicationActivated, windowID: nil)
        ]))

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testAXFocusEventForHiddenWindowDoesNotRollBackWorkspace() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchWorkspace(to: "2")
        windowSystem.focusedWindowIDValue = 100
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ]))

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertTrue(controller.isHiddenByWorkspace(100))
    }

    func testDisplayAndFocusEventsInOneBatchBothApply() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindowIDValue = 200
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .displayChanged, windowID: nil),
            WindowRuntimeEvent(kind: .applicationActivated, windowID: nil)
        ]))

        XCTAssertEqual(controller.currentWorkspace, "2")
        XCTAssertFalse(controller.isHiddenByWorkspace(200))
    }

    func testLayoutEventForHiddenFocusedWindowDoesNotSwitchWorkspace() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
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
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.focusedWindowIDValue = 200
        windowSystem.frameWriteFailures.insert(200)
        var switcherRefreshCount = 0
        var surfaceRefreshCount = 0
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: { switcherRefreshCount += 1 },
            refreshStatusSurfaces: { surfaceRefreshCount += 1 }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .applicationActivated, windowID: nil)
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
            refreshStatusSurfaces: {}
        )
    }
}
