import ApplicationServices
@testable import CosmosApp
import CosmosCore
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
        XCTAssertEqual(batch.windowIDsNeedingCapture, [100])
    }

    func testDisplayChangeIsRecognizedAsTopologyAndFullThumbnailChange() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .displayChanged, windowID: nil)
        ])

        XCTAssertTrue(batch.containsDisplayChange)
        XCTAssertTrue(batch.needsFullThumbnailRefresh)
    }

    func testCreatedWindowRequiresFullDiscovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: 100)
        ])

        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeRequiresFullDiscovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil)
        ])

        XCTAssertTrue(batch.containsSessionResume)
        XCTAssertTrue(batch.isSessionResumeRecovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeMixedWithWindowSetChangeIsNotRecoveryOnly() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ])

        XCTAssertFalse(batch.isSessionResumeRecovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeMixedWithFocusChangeRemainsRecovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ])

        XCTAssertTrue(batch.isSessionResumeRecovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testExistingWindowChangesDiscoverOnlyAffectedWindows() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 100),
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 200)
        ])

        XCTAssertEqual(batch.discoveryWindowIDs, [100, 200])
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
            WindowRuntimeEventKind.kinds(forAXNotification: kAXUIElementDestroyedNotification as String),
            [.windowDestroyed]
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

    func testAXFocusChangeIsAcceptedOnlyForTheFrontmostApplication() {
        XCTAssertTrue(AXFocusChangeFilter.acceptsFocusChange(
            sourcePID: 100,
            frontmostPID: 100
        ))
        XCTAssertFalse(AXFocusChangeFilter.acceptsFocusChange(
            sourcePID: 100,
            frontmostPID: 200
        ))
        XCTAssertFalse(AXFocusChangeFilter.acceptsFocusChange(
            sourcePID: 100,
            frontmostPID: nil
        ))
    }

    func testLayoutChangeFollowsFocusOnlyWhenItChangedTheFocusedWindow() {
        let focusedWindowLayout = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 100)
        ])
        let otherWindowLayout = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 200)
        ])
        let destroyedWindow = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: 200)
        ])
        let destroyedUnknownWindow = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: nil)
        ])
        let unrelatedWindowSetChange = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 200),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: 300)
        ])

        XCTAssertTrue(focusedWindowLayout.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 100,
            liveWindowIDs: [100, 200]
        ))
        XCTAssertFalse(otherWindowLayout.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 100,
            liveWindowIDs: [100, 200]
        ))
        XCTAssertTrue(destroyedWindow.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 200,
            liveWindowIDs: [100]
        ))
        XCTAssertFalse(destroyedWindow.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 300,
            liveWindowIDs: [100, 300]
        ))
        XCTAssertTrue(destroyedUnknownWindow.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 200,
            liveWindowIDs: [100]
        ))
        XCTAssertFalse(destroyedUnknownWindow.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 200,
            liveWindowIDs: [100, 200]
        ))
        XCTAssertFalse(unrelatedWindowSetChange.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 100,
            liveWindowIDs: [100, 200, 300]
        ))
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
            },
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        ]))

        XCTAssertEqual(switcherRefreshCount, 1)
        XCTAssertEqual(surfaceRefreshCount, 1)
    }

    func testApplicationActivationSwitchesToTheFocusedWindowsSpace() throws {
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

        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertFalse(controller.isHiddenBySpace(200))
    }

    func testAXFocusEventForHiddenWindowDoesNotRollBackSpace() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "One"),
            makeSwitcherTestWindow(id: 200, title: "Two")
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchSpace(to: "2")
        windowSystem.focusedWindowIDValue = 100
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ]))

        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertTrue(controller.isHiddenBySpace(100))
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

        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertFalse(controller.isHiddenBySpace(200))
    }

    func testLayoutEventForHiddenFocusedWindowDoesNotSwitchSpace() throws {
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

        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertTrue(controller.isHiddenBySpace(200))
    }

    func testUnrelatedWindowEventsDoNotUndoExplicitSpaceSwitch() throws {
        let displays = [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                role: .main
            ),
            DisplaySnapshot(
                id: 2,
                frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000),
                role: .extended
            )
        ]
        let (controller, windowSystem) = try makeSwitcherTestController(
            windows: [
                makeSwitcherTestWindow(id: 100, title: "Main"),
                makeSwitcherTestWindow(
                    id: 200,
                    title: "Secondary",
                    frame: WindowFrame(
                        origin: CGPoint(x: 1100, y: 100),
                        size: CGSize(width: 200, height: 120)
                    )
                ),
                makeSwitcherTestWindow(id: 300, title: "Closing")
            ],
            displays: displays
        )
        try controller.applyConfig(CosmosConfig(
            spaces: [
                SpaceConfig(id: "A", display: 1),
                SpaceConfig(id: "B", display: 2)
            ]
        ))
        _ = try controller.switchSpace(to: "B")
        windowSystem.focusedWindowIDValue = 100
        let handler = makeHandler(controller: controller)

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 200)
        ]))

        XCTAssertEqual(controller.currentSpace, "B")
        XCTAssertEqual(Set(controller.visibleSpaces), ["A", "B"])

        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 100, title: "Main"),
            makeSwitcherTestWindow(
                id: 200,
                title: "Secondary",
                frame: WindowFrame(
                    origin: CGPoint(x: 1100, y: 100),
                    size: CGSize(width: 200, height: 120)
                )
            )
        ])
        windowSystem.focusedWindowIDValue = 100

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: 300)
        ]))

        XCTAssertEqual(controller.currentSpace, "B")
        XCTAssertEqual(Set(controller.visibleSpaces), ["A", "B"])
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

    private func makeHandler(
        controller: SpaceController,
        previewService: SwitcherPreviewService? = nil
    ) -> WindowRuntimeEventHandler {
        WindowRuntimeEventHandler(
            controller: controller,
            previewService: previewService ?? makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )
    }
}

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
