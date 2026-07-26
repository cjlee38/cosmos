import AppKit
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceThumbnailAndLayoutTests: XCTestCase {
    func testSpaceThumbnailGeometryMapsTheDesktopTopLeftIntoTheImageInset() {
        let frame = SpaceThumbnailRenderer.previewFrame(
            for: CGRect(x: 0, y: 0, width: 50, height: 50),
            desktopBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            imageSize: CGSize(width: 120, height: 120)
        )

        XCTAssertEqual(frame, CGRect(x: 10, y: 60, width: 50, height: 50))
    }

    func testSpaceThumbnailUsesAssignedDisplayWhenSpaceIsEmpty() throws {
        let displayFrame = CGRect(x: 1000, y: 0, width: 1600, height: 900)
        let renderGroup = try XCTUnwrap(SpaceThumbnailRenderer.makeRenderGroups([
            thumbnailGroup(id: "1", displayFrame: displayFrame)
        ]).first)

        XCTAssertEqual(renderGroup.desktopBounds, displayFrame)
    }

    func testSpaceThumbnailDoesNotExpandWhenAWindowSpansDisplays() throws {
        let displayFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let spanningWindow = WindowSwitcherItem(
            windowID: 10,
            pid: 1,
            appName: "App",
            title: "Window",
            frame: WindowFrame(
                origin: CGPoint(x: 900, y: 100),
                size: CGSize(width: 300, height: 400)
            ),
            preview: nil,
            icon: nil
        )
        let renderGroup = try XCTUnwrap(SpaceThumbnailRenderer.makeRenderGroups([
            thumbnailGroup(id: "1", displayFrame: displayFrame, windows: [spanningWindow])
        ]).first)

        XCTAssertEqual(renderGroup.desktopBounds, displayFrame)
    }

    func testSpaceThumbnailCacheDoesNotPublishSupersededRender() {
        let firstRenderStarted = expectation(description: "first render started")
        let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
        let updatePublished = expectation(description: "latest render published")
        var renderCount = 0
        let cache = SpaceThumbnailCache { _ in
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

    func testSpaceThumbnailCachePublishesEachSpaceWithoutWaitingForTheBatch() {
        let secondRenderStarted = expectation(description: "second render started")
        let allowSecondRenderToFinish = DispatchSemaphore(value: 0)
        let firstUpdatePublished = expectation(description: "first space published")
        let secondUpdatePublished = expectation(description: "second space published")
        let cache = SpaceThumbnailCache { group in
            if group.id == "2" {
                secondRenderStarted.fulfill()
                allowSecondRenderToFinish.wait()
            }
            return makeSwitcherTestImage()
        }
        cache.setUpdateHandler { spaceIDs in
            if spaceIDs == ["1"] {
                firstUpdatePublished.fulfill()
            }
            if spaceIDs == ["2"] {
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

    func testSpaceRenderingDoesNotWaitForWindowCaptureCycle() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        let captureStarted = expectation(description: "window capture started")
        let allowCaptureToFinish = DispatchSemaphore(value: 0)
        let spaceRenderStarted = expectation(description: "space render started")
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in
                captureStarted.fulfill()
                allowCaptureToFinish.wait()
                return makeSwitcherTestImage()
            },
            renderSpace: { _ in
                spaceRenderStarted.fulfill()
                return makeSwitcherTestImage()
            }
        )

        service.refresh(windowIDs: [10], spaceIDs: ["1"])

        wait(for: [captureStarted, spaceRenderStarted], timeout: 1)
        allowCaptureToFinish.signal()
    }

    func testSpaceThumbnailCachePromotesPriorityRenderAlreadyInQueue() {
        let firstRenderStarted = expectation(description: "first render started")
        let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
        let priorityRenderStarted = expectation(description: "priority render started")
        var renderOrder: [String] = []
        let cache = SpaceThumbnailCache { group in
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
            prioritySpaceIDs: ["3"]
        )
        allowFirstRenderToFinish.signal()

        wait(for: [priorityRenderStarted], timeout: 1)
        XCTAssertEqual(Array(renderOrder.prefix(2)), ["1", "3"])
    }

    func testSpaceThumbnailCacheRejectsRenderFromRemovedSpaceGeneration() {
        let firstRenderStarted = expectation(description: "first render started")
        let allowFirstRenderToFinish = DispatchSemaphore(value: 0)
        let currentRenderPublished = expectation(description: "current render published")
        var renderCount = 0
        var updateCount = 0
        let cache = SpaceThumbnailCache { _ in
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

    func testSpaceThumbnailCacheDoesNotPublishRenderAfterInvalidation() {
        let renderStarted = expectation(description: "render started")
        let allowRenderToFinish = DispatchSemaphore(value: 0)
        let updatePublished = expectation(description: "invalidated render is not published")
        updatePublished.isInverted = true
        let cache = SpaceThumbnailCache { _ in
            renderStarted.fulfill()
            allowRenderToFinish.wait()
            return makeSwitcherTestImage()
        }
        cache.setUpdateHandler { _ in updatePublished.fulfill() }
        cache.removeStaleThumbnails(keeping: ["1"])
        cache.refresh(groups: [thumbnailGroup(id: "1")])
        wait(for: [renderStarted], timeout: 1)

        cache.invalidate()
        allowRenderToFinish.signal()

        wait(for: [updatePublished], timeout: 0.25)
        XCTAssertNil(cache.thumbnail(for: "1"))
    }

    private func thumbnailGroup(
        id: String,
        displayFrame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 800),
        windows: [WindowSwitcherItem] = []
    ) -> SpaceSwitcherGroup {
        SpaceSwitcherGroup(
            id: id,
            displayFrame: displayFrame,
            windows: windows,
            preview: nil
        )
    }
}
