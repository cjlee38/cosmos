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

        service.refresh(windowIDs: [10], workspaceNames: ["1"])
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

    func testWorkspaceGroupUsesAliasForDisplayAndIDForIdentity() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        try controller.applyConfig(KkaciConfig(workspaces: [
            WorkspaceConfig(id: "1", name: "Develop")
        ]))
        let service = makeSwitcherTestPreviewService(controller: controller)

        let group = try XCTUnwrap(service.workspaceGroups(ids: ["1"]).first)

        XCTAssertEqual(group.id, "1")
        XCTAssertEqual(group.displayName, "Develop")
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
        var receivedWorkspaceNames: Set<String> = []
        service.setUpdateHandler { update in
            guard update.windowIDs.contains(10) else {
                return
            }
            receivedWindowIDs = update.windowIDs
            receivedWorkspaceNames = update.workspaceNames
            updateReceived.fulfill()
        }

        service.refresh(windowIDs: [10], workspaceNames: [])

        wait(for: [updateReceived], timeout: 1)
        XCTAssertEqual(receivedWindowIDs, [10])
        XCTAssertTrue(receivedWorkspaceNames.isEmpty)
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

        service.refresh(windowIDs: [10], workspaceNames: [])
        waitUntil { service.windowItems(ids: [10]).first?.preview != nil }

        lock.lock()
        capturedImage = nil
        lock.unlock()
        service.refresh(windowIDs: [10], workspaceNames: [])
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

        service.refresh(windowIDs: [], workspaceNames: [])
        wait(for: [loadStarted], timeout: 1)

        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 10, title: "Existing", pid: 7),
            makeSwitcherTestWindow(id: 20, title: "New", pid: 7)
        ])
        _ = try controller.handleWindowSetChanged()
        service.refresh(windowIDs: [], workspaceNames: [])
        allowLoadToFinish.signal()

        wait(for: [currentWindowsUpdated], timeout: 1)
        XCTAssertNotNil(service.windowItems(ids: [20]).first?.icon)
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
}
