import AppKit
@testable import KkaciApp
import KkaciCore
import XCTest

final class SwitcherPreviewServiceTests: XCTestCase {
    func testWindowItemsAndWorkspaceGroupsProjectLatestCoreStateFromTheSameCaches() throws {
        let initialWindow = makeSwitcherTestWindow(id: 10, title: "Initial", pid: 7)
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [initialWindow])
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in makeSwitcherTestImage() },
            loadIcon: { _ in icon }
        )

        service.refresh(windowIDs: [10], workspaceIDs: ["1"])
        waitUntil {
            let item = service.windowItems(ids: [10]).first
            return item?.preview != nil && item?.icon != nil
        }

        let updatedFrame = WindowFrame(
            origin: CGPoint(x: 40, y: 50),
            size: CGSize(width: 300, height: 180)
        )
        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 10, title: "Updated", pid: 7, frame: updatedFrame)
        ])
        _ = try controller.handleWindowSetChanged()

        let item = try XCTUnwrap(service.windowItems(ids: [10]).first)
        let groupItem = try XCTUnwrap(service.workspaceGroups(ids: ["1"]).first?.windows.first)

        XCTAssertEqual(item.title, "Updated")
        XCTAssertEqual(item.frame, updatedFrame)
        XCTAssertTrue(item.preview === groupItem.preview)
        XCTAssertTrue(item.icon === groupItem.icon)
        XCTAssertTrue(service.windowItems(ids: [999]).isEmpty)
        XCTAssertEqual(service.workspaceGroups(ids: ["missing"]).count, 0)
    }

    func testWorkspaceGroupUsesWorkspaceID() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        try controller.applyConfig(KkaciConfig(workspaces: [
            WorkspaceConfig(id: "1")
        ]))
        let service = makeSwitcherTestPreviewService(controller: controller)

        let group = try XCTUnwrap(service.workspaceGroups(ids: ["1"]).first)

        XCTAssertEqual(group.id, "1")
    }

    func testWorkspaceGroupUsesItsEffectiveDisplayFrame() throws {
        let mainFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let extendedFrame = CGRect(x: 1000, y: 0, width: 1600, height: 900)
        let (controller, _) = try makeSwitcherTestController(
            windows: [],
            displays: [
                DisplaySnapshot(id: 1, frame: mainFrame, role: .main),
                DisplaySnapshot(id: 2, frame: extendedFrame, role: .extended)
            ]
        )
        try controller.applyConfig(KkaciConfig(workspaces: [
            WorkspaceConfig(id: "1", display: 1),
            WorkspaceConfig(id: "2", display: 2)
        ]))
        let service = makeSwitcherTestPreviewService(controller: controller)

        let groups = service.workspaceGroups(ids: ["1", "2"])

        XCTAssertEqual(groups.map(\.displayFrame), [mainFrame, extendedFrame])
    }

    func testThumbnailCompletionReportsOnlyTheAffectedWindow() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two")
        ])
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in makeSwitcherTestImage() }
        )
        let updateReceived = expectation(description: "preview update")
        var receivedWindowIDs: Set<WindowID> = []
        var receivedWorkspaceIDs: Set<String> = []
        service.setUpdateHandler { update in
            guard update.windowIDs.contains(10) else {
                return
            }
            receivedWindowIDs = update.windowIDs
            receivedWorkspaceIDs = update.workspaceIDs
            updateReceived.fulfill()
        }

        service.refresh(windowIDs: [10], workspaceIDs: [])

        wait(for: [updateReceived], timeout: 1)
        XCTAssertEqual(receivedWindowIDs, [10])
        XCTAssertTrue(receivedWorkspaceIDs.isEmpty)
    }

    func testFailedThumbnailRecaptureRemovesThePreviousPreview() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        let lock = NSLock()
        var capturedImage: CGImage? = makeSwitcherTestImage()
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in
                lock.lock()
                defer { lock.unlock() }
                return capturedImage
            }
        )

        service.refresh(windowIDs: [10], workspaceIDs: [])
        waitUntil { service.windowItems(ids: [10]).first?.preview != nil }

        lock.lock()
        capturedImage = nil
        lock.unlock()
        service.refresh(windowIDs: [10], workspaceIDs: [])
        waitUntil { service.windowItems(ids: [10]).first?.preview == nil }

        XCTAssertNil(service.windowItems(ids: [10]).first?.preview)
    }

    func testIconCompletionUsesCurrentWindowsForAnInFlightProcess() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "Existing", pid: 7)
        ])
        let loadStarted = expectation(description: "icon load started")
        let allowLoadToFinish = DispatchSemaphore(value: 0)
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            loadIcon: { _ in
                loadStarted.fulfill()
                allowLoadToFinish.wait()
                return NSImage(size: NSSize(width: 16, height: 16))
            }
        )
        let currentWindowsUpdated = expectation(description: "current windows receive icon update")
        service.setUpdateHandler { update in
            if update.windowIDs == [10, 20] {
                currentWindowsUpdated.fulfill()
            }
        }

        service.refresh(windowIDs: [], workspaceIDs: [])
        wait(for: [loadStarted], timeout: 1)

        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 10, title: "Existing", pid: 7),
            makeSwitcherTestWindow(id: 20, title: "New", pid: 7)
        ])
        _ = try controller.handleWindowSetChanged()
        service.refresh(windowIDs: [], workspaceIDs: [])
        allowLoadToFinish.signal()

        wait(for: [currentWindowsUpdated], timeout: 1)
        XCTAssertNotNil(service.windowItems(ids: [20]).first?.icon)
    }
}

extension SwitcherPreviewServiceTests {
    func testWorkspaceThumbnailGeometryMapsTheDesktopTopLeftIntoTheImageInset() {
        let frame = WorkspaceThumbnailRenderer.previewFrame(
            for: CGRect(x: 0, y: 0, width: 50, height: 50),
            desktopBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            imageSize: CGSize(width: 120, height: 120)
        )

        XCTAssertEqual(frame, CGRect(x: 10, y: 60, width: 50, height: 50))
    }

    func testWorkspaceThumbnailUsesAssignedDisplayWhenWorkspaceIsEmpty() throws {
        let displayFrame = CGRect(x: 1000, y: 0, width: 1600, height: 900)
        let renderGroup = try XCTUnwrap(WorkspaceThumbnailRenderer.makeRenderGroups([
            thumbnailGroup(id: "1", displayFrame: displayFrame)
        ]).first)

        XCTAssertEqual(renderGroup.desktopBounds, displayFrame)
    }

    func testWorkspaceThumbnailDoesNotExpandWhenAWindowSpansDisplays() throws {
        let displayFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let spanningWindow = WindowSwitcherItem(
            windowID: 10,
            appName: "App",
            title: "Window",
            frame: WindowFrame(
                origin: CGPoint(x: 900, y: 100),
                size: CGSize(width: 300, height: 400)
            ),
            preview: nil,
            icon: nil
        )
        let renderGroup = try XCTUnwrap(WorkspaceThumbnailRenderer.makeRenderGroups([
            thumbnailGroup(id: "1", displayFrame: displayFrame, windows: [spanningWindow])
        ]).first)

        XCTAssertEqual(renderGroup.desktopBounds, displayFrame)
    }

    func testWorkspaceThumbnailCacheDoesNotPublishSupersededRender() {
        let firstRenderStarted = expectation(description: "first render started")
        let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
        let updatePublished = expectation(description: "latest render published")
        var renderCount = 0
        let cache = WorkspaceThumbnailCache { _ in
            renderCount += 1
            if renderCount == 1 {
                firstRenderStarted.fulfill()
                allowFirstRenderToFinish.wait()
            }
            return makeSwitcherTestImage()
        }
        var updates: [Set<String>] = []
        cache.setUpdateHandler {
            updates.append($0)
            updatePublished.fulfill()
        }
        cache.removeStaleThumbnails(keeping: ["1"])

        cache.refresh(groups: [thumbnailGroup(id: "1")])
        wait(for: [firstRenderStarted], timeout: 1)
        cache.refresh(groups: [thumbnailGroup(id: "1")])
        allowFirstRenderToFinish.signal()

        wait(for: [updatePublished], timeout: 1)
        XCTAssertEqual(updates, [["1"]])
        XCTAssertEqual(renderCount, 2)
    }

    func testWorkspaceThumbnailCachePublishesEachWorkspaceWithoutWaitingForTheBatch() {
        let secondRenderStarted = expectation(description: "second render started")
        let allowSecondRenderToFinish = DispatchSemaphore(value: 0)
        let firstUpdatePublished = expectation(description: "first workspace published")
        let secondUpdatePublished = expectation(description: "second workspace published")
        let cache = WorkspaceThumbnailCache { group in
            if group.id == "2" {
                secondRenderStarted.fulfill()
                allowSecondRenderToFinish.wait()
            }
            return makeSwitcherTestImage()
        }
        cache.setUpdateHandler { workspaceIDs in
            if workspaceIDs == ["1"] {
                firstUpdatePublished.fulfill()
            }
            if workspaceIDs == ["2"] {
                secondUpdatePublished.fulfill()
            }
        }
        cache.removeStaleThumbnails(keeping: ["1", "2"])

        cache.refresh(
            groups: [thumbnailGroup(id: "1"), thumbnailGroup(id: "2")]
        )

        wait(for: [firstUpdatePublished, secondRenderStarted], timeout: 1)
        XCTAssertNotNil(cache.thumbnail(for: "1"))
        XCTAssertNil(cache.thumbnail(for: "2"))
        allowSecondRenderToFinish.signal()
        wait(for: [secondUpdatePublished], timeout: 1)
    }

    func testWorkspaceRenderingDoesNotWaitForWindowCaptureCycle() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        let captureStarted = expectation(description: "window capture started")
        let allowCaptureToFinish = DispatchSemaphore(value: 0)
        let workspaceRenderStarted = expectation(description: "workspace render started")
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in
                captureStarted.fulfill()
                allowCaptureToFinish.wait()
                return makeSwitcherTestImage()
            },
            renderWorkspace: { _ in
                workspaceRenderStarted.fulfill()
                return makeSwitcherTestImage()
            }
        )

        service.refresh(windowIDs: [10], workspaceIDs: ["1"])

        wait(for: [captureStarted, workspaceRenderStarted], timeout: 1)
        allowCaptureToFinish.signal()
    }

    func testWorkspaceThumbnailCachePromotesPriorityRenderAlreadyInQueue() {
        let firstRenderStarted = expectation(description: "first render started")
        let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
        let priorityRenderStarted = expectation(description: "priority render started")
        var renderOrder: [String] = []
        let cache = WorkspaceThumbnailCache { group in
            renderOrder.append(group.id)
            if group.id == "1" {
                firstRenderStarted.fulfill()
                allowFirstRenderToFinish.wait()
            } else if group.id == "3" {
                priorityRenderStarted.fulfill()
            }
            return makeSwitcherTestImage()
        }
        cache.removeStaleThumbnails(keeping: ["1", "2", "3"])
        cache.refresh(
            groups: [thumbnailGroup(id: "1"), thumbnailGroup(id: "2"), thumbnailGroup(id: "3")]
        )
        wait(for: [firstRenderStarted], timeout: 1)

        cache.refresh(
            groups: [thumbnailGroup(id: "3")],
            priorityWorkspaceIDs: ["3"]
        )
        allowFirstRenderToFinish.signal()

        wait(for: [priorityRenderStarted], timeout: 1)
        XCTAssertEqual(Array(renderOrder.prefix(2)), ["1", "3"])
    }

    func testWorkspaceThumbnailCacheRejectsRenderFromRemovedWorkspaceGeneration() {
        let firstRenderStarted = expectation(description: "first render started")
        let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
        let currentRenderPublished = expectation(description: "current render published")
        var renderCount = 0
        var updateCount = 0
        let cache = WorkspaceThumbnailCache { _ in
            renderCount += 1
            if renderCount == 1 {
                firstRenderStarted.fulfill()
                allowFirstRenderToFinish.wait()
            }
            return makeSwitcherTestImage()
        }
        cache.setUpdateHandler { _ in
            updateCount += 1
            currentRenderPublished.fulfill()
        }
        cache.removeStaleThumbnails(keeping: ["1"])
        cache.refresh(groups: [thumbnailGroup(id: "1")])
        wait(for: [firstRenderStarted], timeout: 1)

        cache.removeStaleThumbnails(keeping: [])
        cache.removeStaleThumbnails(keeping: ["1"])
        cache.refresh(groups: [thumbnailGroup(id: "1")])
        allowFirstRenderToFinish.signal()

        wait(for: [currentRenderPublished], timeout: 1)
        XCTAssertEqual(renderCount, 2)
        XCTAssertEqual(updateCount, 1)
    }

    func testWorkspaceOverviewCardsNeverExceedTheirGridCells() {
        let layout = WorkspaceOverviewLayout(
            groupCount: 36,
            availableFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            size: 0
        )

        XCTAssertGreaterThan(layout.cardSize.width, 0)
        XCTAssertGreaterThan(layout.cardSize.height, 0)
        for row in 0 ..< 6 {
            for column in 0 ..< 6 {
                let cell = layout.cellFrame(row: row, column: column)
                XCTAssertLessThanOrEqual(layout.cardSize.width, cell.width)
                XCTAssertLessThanOrEqual(layout.cardSize.height, cell.height)
            }
        }
    }

    func testWorkspaceOverviewContentFitsThreeCardsWithoutVerticalCellPadding() {
        let layout = WorkspaceOverviewLayout(
            groupCount: 3,
            availableFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            size: 0.5
        )

        let cell = layout.cellFrame(row: 0, column: 0)
        XCTAssertEqual(layout.cardSize.height, cell.height, accuracy: 1)
        XCTAssertEqual(layout.contentSize.height, layout.cardSize.height, accuracy: 1)
    }

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertTrue(condition())
    }

    private func thumbnailGroup(
        id: String,
        displayFrame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 800),
        windows: [WindowSwitcherItem] = []
    ) -> WorkspaceSwitcherGroup {
        WorkspaceSwitcherGroup(
            id: id,
            displayFrame: displayFrame,
            windows: windows,
            preview: nil
        )
    }
}
