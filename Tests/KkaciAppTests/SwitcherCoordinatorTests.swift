@testable import KkaciApp
import KkaciCore
import XCTest

final class SwitcherCoordinatorTests: XCTestCase {
    func testContentChangeBeforePresentationUsesTheLatestWindowSet() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two")
        ])
        let overlay = SwitcherOverlaySpy()
        let shown = expectation(description: "window overlay shown")
        overlay.onWindowShown = shown.fulfill
        let coordinator = makeCoordinator(controller: controller, overlay: overlay)
        coordinator.stepWindow(direction: .forward, wraps: true)

        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 30, title: "Three")
        ])
        _ = try controller.handleWindowSetChanged()
        coordinator.handleContentChanged()

        wait(for: [shown], timeout: 1)
        XCTAssertEqual(overlay.shownWindowIDs, [[10, 30]])
        XCTAssertEqual(overlay.shownWindowSelections, [30])

        coordinator.commitWindowSelection()

        XCTAssertEqual(windowSystem.focusedWindowIDs, [30])
    }

    func testVisibleContentRebindPreservesTheSelectedWindow() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two"),
            makeSwitcherTestWindow(id: 30, title: "Three")
        ])
        let overlay = SwitcherOverlaySpy()
        let shown = expectation(description: "window overlay shown")
        overlay.onWindowShown = shown.fulfill
        let coordinator = makeCoordinator(controller: controller, overlay: overlay)
        coordinator.stepWindow(direction: .forward, wraps: true)
        wait(for: [shown], timeout: 1)

        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 30, title: "Three"),
            makeSwitcherTestWindow(id: 20, title: "Two"),
            makeSwitcherTestWindow(id: 10, title: "One")
        ])
        _ = try controller.handleWindowSetChanged()
        coordinator.handleContentChanged()

        XCTAssertEqual(overlay.reboundWindowIDs, [[30, 20, 10]])
        XCTAssertEqual(overlay.reboundWindowSelections, [20])

        coordinator.commitWindowSelection()

        XCTAssertEqual(windowSystem.focusedWindowIDs, [20])
    }

    func testRemovedSelectedWorkspaceCannotBeRecreatedOnCommit() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let coordinator = makeCoordinator(controller: controller)
        coordinator.stepWorkspace(direction: .forward)

        try controller.applyConfig(KkaciConfig(
            workspaces: [
                WorkspaceConfig(name: "1"),
                WorkspaceConfig(name: "3")
            ]
        ))
        coordinator.handleContentChanged()
        coordinator.commitWorkspaceSelection()

        XCTAssertEqual(controller.workspaces, ["1", "3"])
        XCTAssertEqual(controller.currentWorkspace, "3")
    }

    func testPreviewCompletionUpdatesOnlyTheAffectedTileAndPreservesSelection() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two")
        ])
        let previewService = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in makeSwitcherTestImage() }
        )
        let overlay = SwitcherOverlaySpy()
        let shown = expectation(description: "window overlay shown")
        let previewUpdated = expectation(description: "window preview updated")
        overlay.onWindowShown = shown.fulfill
        overlay.onWindowPreviewsUpdated = previewUpdated.fulfill
        let coordinator = SwitcherCoordinator(
            controller: controller,
            previewService: previewService,
            refreshStatus: {},
            overlay: overlay,
            makeOverlay: { overlay }
        )

        coordinator.stepWindow(direction: .forward, wraps: true)
        wait(for: [shown, previewUpdated], timeout: 1)

        XCTAssertEqual(overlay.updatedWindowIDs, [[10, 20]])
        XCTAssertTrue(overlay.reboundWindowIDs.isEmpty)

        coordinator.commitWindowSelection()
        XCTAssertEqual(windowSystem.focusedWindowIDs, [20])
    }

    func testQuickWindowTapCommitsWithoutCreatingOverlayOrCapturingThumbnails() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two")
        ])
        let overlayCreated = expectation(description: "overlay is not created")
        overlayCreated.isInverted = true
        let thumbnailCaptured = expectation(description: "thumbnail is not captured")
        thumbnailCaptured.isInverted = true
        let previewService = makeSwitcherTestPreviewService(
            controller: controller,
            captureImage: { _ in
                thumbnailCaptured.fulfill()
                return nil
            }
        )
        let coordinator = SwitcherCoordinator(
            controller: controller,
            previewService: previewService,
            refreshStatus: {},
            makeOverlay: {
                overlayCreated.fulfill()
                return SwitcherOverlaySpy()
            }
        )

        coordinator.stepWindow(direction: .forward, wraps: true)
        coordinator.commitWindowSelection()

        wait(for: [overlayCreated, thumbnailCaptured], timeout: 0.25)
        XCTAssertEqual(windowSystem.focusedWindowIDs, [20])
    }

    private func makeCoordinator(
        controller: WorkspaceController,
        overlay: SwitcherOverlaySpy = SwitcherOverlaySpy()
    ) -> SwitcherCoordinator {
        SwitcherCoordinator(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshStatus: {},
            overlay: overlay,
            makeOverlay: { overlay }
        )
    }
}
