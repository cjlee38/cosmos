import ApplicationServices
@testable import CosmosApp
import CosmosCore
import XCTest

final class WindowRuntimeEventHandlerTests: XCTestCase {
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
        XCTAssertFalse(unrelatedWindowSetChange.shouldFollowVisibleFocusedWindow(
            focusedWindowID: 100,
            previouslyFocusedWindowID: 100,
            liveWindowIDs: [100, 200, 300]
        ))
    }

    func testDestroyedWindowFollowsFocusOnlyWhenThePreviouslyFocusedWindowDisappeared() {
        let destroyedWindow = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: 200)
        ])
        let destroyedUnknownWindow = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: nil)
        ])

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
    }

    func testApplicationTerminationCarriesTheTerminatedProcessID() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .applicationTerminated, windowID: nil, processID: 42),
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: 100)
        ])

        XCTAssertEqual(batch.terminatedApplicationPIDs, [42])
        XCTAssertEqual(batch.destroyedWindowIDs, [100])
        XCTAssertTrue(batch.containsWindowSetChange)
        XCTAssertNil(batch.discoveryWindowIDs)
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
        let fixture = try makeExplicitlySwitchedController()
        let controller = fixture.controller
        let windowSystem = fixture.windowSystem

        fixture.handler.handle(WindowRuntimeEventBatch(events: [
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

        fixture.handler.handle(WindowRuntimeEventBatch(events: [
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
}

private struct ExplicitSwitchFixture {
    let controller: SpaceController
    let windowSystem: SwitcherTestWindowSystem
    let handler: WindowRuntimeEventHandler
}

private extension WindowRuntimeEventHandlerTests {
    func makeExplicitlySwitchedController() throws -> ExplicitSwitchFixture {
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
        return ExplicitSwitchFixture(
            controller: controller,
            windowSystem: windowSystem,
            handler: makeHandler(controller: controller)
        )
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
