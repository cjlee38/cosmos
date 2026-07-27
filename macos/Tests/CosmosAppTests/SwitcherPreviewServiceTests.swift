import AppKit
@testable import CosmosApp
import CosmosCore
import XCTest

final class SwitcherPreviewServiceTests: XCTestCase {
    func testWindowItemsAndSpaceGroupsProjectLatestCoreStateFromTheSameCaches() throws {
        let initialWindow = makeSwitcherTestWindow(id: 10, title: "Initial", pid: 7)
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [initialWindow])
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in makeSwitcherTestImage() },
            loadIcon: { _ in icon }
        )

        service.refresh(windowIDs: [10], spaceIDs: ["1"])
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
        let groupItem = try XCTUnwrap(service.spaceGroups(ids: ["1"]).first?.windows.first)

        XCTAssertEqual(item.title, "Updated")
        XCTAssertEqual(item.frame, updatedFrame)
        XCTAssertTrue(item.preview === groupItem.preview)
        XCTAssertTrue(item.icon === groupItem.icon)
        XCTAssertTrue(service.windowItems(ids: [999]).isEmpty)
        XCTAssertEqual(service.spaceGroups(ids: ["missing"]).count, 0)
    }

    func testSpaceGroupUsesSpaceID() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        try controller.applyConfig(CosmosConfig(spaces: [
            SpaceConfig(id: "1")
        ]))
        let service = makeSwitcherTestPreviewService(controller: controller)

        let group = try XCTUnwrap(service.spaceGroups(ids: ["1"]).first)

        XCTAssertEqual(group.id, "1")
    }

    func testSpaceGroupUsesItsEffectiveDisplayFrame() throws {
        let mainFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let extendedFrame = CGRect(x: 1000, y: 0, width: 1600, height: 900)
        let (controller, _) = try makeSwitcherTestController(
            windows: [],
            displays: [
                DisplaySnapshot(id: 1, frame: mainFrame, role: .main),
                DisplaySnapshot(id: 2, frame: extendedFrame, role: .extended)
            ]
        )
        try controller.applyConfig(CosmosConfig(spaces: [
            SpaceConfig(id: "1", display: 1),
            SpaceConfig(id: "2", display: 2)
        ]))
        let service = makeSwitcherTestPreviewService(controller: controller)

        let groups = service.spaceGroups(ids: ["1", "2"])

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
        var receivedSpaceIDs: Set<String> = []
        service.setUpdateHandler { update in
            guard update.windowIDs.contains(10) else {
                return
            }
            receivedWindowIDs = update.windowIDs
            receivedSpaceIDs = update.spaceIDs
            updateReceived.fulfill()
        }

        service.refresh(windowIDs: [10], spaceIDs: [])

        wait(for: [updateReceived], timeout: 1)
        XCTAssertEqual(receivedWindowIDs, [10])
        XCTAssertTrue(receivedSpaceIDs.isEmpty)
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

        service.refresh(windowIDs: [10], spaceIDs: [])
        waitUntil { service.windowItems(ids: [10]).first?.preview != nil }

        lock.lock()
        capturedImage = nil
        lock.unlock()
        service.markWindowThumbnailsDirty([10])
        service.refresh(windowIDs: [10], spaceIDs: [])
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

        service.refresh(windowIDs: [], spaceIDs: [])
        wait(for: [loadStarted], timeout: 1)

        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 10, title: "Existing", pid: 7),
            makeSwitcherTestWindow(id: 20, title: "New", pid: 7)
        ])
        _ = try controller.handleWindowSetChanged()
        service.refresh(windowIDs: [], spaceIDs: [])
        allowLoadToFinish.signal()

        wait(for: [currentWindowsUpdated], timeout: 1)
        XCTAssertNotNil(service.windowItems(ids: [20]).first?.icon)
    }

    func testMissingScreenCapturePermissionSkipsCaptureAndUsesNativeApplicationIcons() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        let captureAttempted = expectation(description: "window capture is not attempted")
        captureAttempted.isInverted = true
        let spaceRendered = expectation(description: "space bitmap is not rendered")
        spaceRendered.isInverted = true
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in
                captureAttempted.fulfill()
                return makeSwitcherTestImage()
            },
            canCapture: { false },
            renderSpace: { _ in
                spaceRendered.fulfill()
                return makeSwitcherTestImage()
            }
        )

        service.refresh(windowIDs: [10], spaceIDs: ["1"])
        let group = try XCTUnwrap(service.spaceGroups(ids: ["1"]).first)

        wait(for: [spaceRendered, captureAttempted], timeout: 0.25)
        XCTAssertEqual(group.previewStyle, .applicationIcons)
        XCTAssertNil(group.preview)
        XCTAssertNil(service.windowItems(ids: [10]).first?.preview)
    }

    func testSpaceGroupProjectionDoesNotRecheckCapturePermission() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        var permissionCheckCount = 0
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            canCapture: {
                permissionCheckCount += 1
                return true
            }
        )

        _ = service.spaceGroups(ids: ["1"])
        _ = service.spaceGroups(ids: ["1"])

        XCTAssertEqual(permissionCheckCount, 1)
    }

    func testWindowThumbnailCompletionsCoalesceSpaceRendering() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two")
        ])
        let rendered = expectation(description: "space rendered")
        let lock = NSLock()
        var renderCount = 0
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in makeSwitcherTestImage() },
            renderSpace: { _ in
                lock.lock()
                renderCount += 1
                lock.unlock()
                rendered.fulfill()
                return makeSwitcherTestImage()
            }
        )

        service.refresh(windowIDs: [10, 20], spaceIDs: [])

        wait(for: [rendered], timeout: 1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        lock.lock()
        let finalRenderCount = renderCount
        lock.unlock()
        XCTAssertEqual(finalRenderCount, 1)
    }

    func testRevokedScreenCapturePermissionImmediatelyStopsUsingCachedSpacePreview() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        var canCapture = true
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            canCapture: { canCapture },
            renderSpace: { _ in makeSwitcherTestImage() }
        )

        service.refreshSpaces(ids: ["1"])
        waitUntil { service.spaceGroups(ids: ["1"]).first?.preview != nil }

        canCapture = false
        service.prepareForPresentation()
        let group = try XCTUnwrap(service.spaceGroups(ids: ["1"]).first)

        XCTAssertEqual(group.previewStyle, .applicationIcons)
        XCTAssertNil(group.preview)
    }
}

final class SwitcherPreviewCaptureEligibilityTests: XCTestCase {
    func testRefreshSkipsWindowWhoseFrameIsTemporarilyUnavailable() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        windowSystem.replaceWindows([
            WindowSnapshot(
                id: 10,
                app: RunningAppInfo(pid: 1, name: "App 1"),
                title: "One",
                frame: nil,
                isMinimized: false
            )
        ])
        _ = try controller.handleWindowSetChanged()
        let captureAttempted = expectation(description: "window capture is not attempted")
        captureAttempted.isInverted = true
        let service = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in
                captureAttempted.fulfill()
                return makeSwitcherTestImage()
            }
        )

        service.refresh(windowIDs: [10], spaceIDs: [])

        wait(for: [captureAttempted], timeout: 0.25)
    }
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
