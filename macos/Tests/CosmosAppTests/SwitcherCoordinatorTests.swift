@testable import CosmosApp
import CosmosCore
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

    func testRemovedSelectedSpaceCannotBeRecreatedOnCommit() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let coordinator = makeCoordinator(controller: controller)
        coordinator.stepSpace(direction: .forward)

        try controller.applyConfig(CosmosConfig(
            spaces: [
                SpaceConfig(id: "1"),
                SpaceConfig(id: "3")
            ]
        ))
        coordinator.handleContentChanged()
        coordinator.commitSpaceSelection()

        XCTAssertEqual(controller.spaces, ["1", "3"])
        XCTAssertEqual(controller.currentSpace, "3")
    }

    func testSpaceSwitcherSelectsThePreviouslyActiveSpaceFirst() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        _ = try controller.switchSpace(to: "2")
        _ = try controller.switchSpace(to: "1")
        let coordinator = makeCoordinator(controller: controller)

        coordinator.stepSpace(direction: .forward)
        coordinator.commitSpaceSelection()

        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertEqual(controller.spacesByRecency, ["2", "1", "3"])
    }

    func testSpaceSwitcherCommitMovesCursorWhenTargetIsOnAnotherDisplay() throws {
        let displays = [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                role: .main
            ),
            DisplaySnapshot(
                id: 2,
                frame: CGRect(x: 1000, y: 0, width: 1200, height: 800),
                role: .extended
            )
        ]
        let controller = SpaceController(
            windowSystem: SwitcherTestWindowSystem(windows: []),
            displayProvider: SwitcherTestDisplayProvider(snapshots: displays),
            configStore: ConfigStoreSpy(loadedConfig: CosmosConfig(spaces: [
                SpaceConfig(id: "1", display: 1),
                SpaceConfig(id: "A", display: 2)
            ]))
        )
        try controller.bootstrapWindowState()
        var cursorPositions: [CGPoint] = []
        let coordinator = SwitcherCoordinator(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            spaceSwitchCommand: SpaceSwitchCommand(
                controller: controller,
                warpCursor: {
                    cursorPositions.append($0)
                    return .success
                }
            ),
            refreshStatus: {},
            overlay: SwitcherOverlaySpy(),
            makeOverlay: SwitcherOverlaySpy.init
        )

        coordinator.stepSpace(direction: .forward)
        coordinator.commitSpaceSelection()

        XCTAssertEqual(controller.currentSpace, "A")
        XCTAssertEqual(cursorPositions, [CGPoint(x: 1600, y: 400)])
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
        overlay.onWindowPreviewsUpdated = {
            let updatedWindowIDs = Set(overlay.updatedWindowIDs.flatMap { $0 })
            guard updatedWindowIDs == [10, 20] else {
                return
            }
            overlay.onWindowPreviewsUpdated = nil
            previewUpdated.fulfill()
        }
        let coordinator = SwitcherCoordinator(
            controller: controller,
            previewService: previewService,
            spaceSwitchCommand: SpaceSwitchCommand(controller: controller, warpCursor: { _ in .success }),
            refreshStatus: {},
            overlay: overlay,
            makeOverlay: { overlay }
        )

        coordinator.stepWindow(direction: .forward, wraps: true)
        wait(for: [shown, previewUpdated], timeout: 1)

        XCTAssertEqual(Set(overlay.updatedWindowIDs.flatMap { $0 }), [10, 20])
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
            spaceSwitchCommand: SpaceSwitchCommand(controller: controller, warpCursor: { _ in .success }),
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

    func testOverlayArrowKeyMovesTheActiveWindowSessionSelection() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two"),
            makeSwitcherTestWindow(id: 30, title: "Three")
        ])
        let overlay = SwitcherOverlaySpy()
        let coordinator = makeCoordinator(controller: controller, overlay: overlay)

        coordinator.stepWindow(direction: .forward, wraps: true)
        overlay.onArrowKey?(.right)
        coordinator.commitWindowSelection()

        XCTAssertEqual(windowSystem.focusedWindowIDs, [30])
    }

    func testOverlayOutsideClickCancelsWithoutCommitting() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 10, title: "One"),
            makeSwitcherTestWindow(id: 20, title: "Two")
        ])
        let overlay = SwitcherOverlaySpy()
        let coordinator = makeCoordinator(controller: controller, overlay: overlay)

        coordinator.stepWindow(direction: .forward, wraps: true)
        overlay.onOutsideClick?()
        coordinator.commitWindowSelection()

        XCTAssertTrue(windowSystem.focusedWindowIDs.isEmpty)
    }

    func testOverlaySpaceKeyCommitsTheMatchingSpace() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let overlay = SwitcherOverlaySpy()
        let coordinator = makeCoordinator(controller: controller, overlay: overlay)

        coordinator.stepSpace(direction: .forward)
        let handled = overlay.onSpaceKey?("3")

        XCTAssertEqual(handled, true)
        XCTAssertEqual(controller.currentSpace, "3")
    }

    private func makeCoordinator(
        controller: SpaceController,
        overlay: SwitcherOverlaySpy = SwitcherOverlaySpy()
    ) -> SwitcherCoordinator {
        SwitcherCoordinator(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            spaceSwitchCommand: SpaceSwitchCommand(controller: controller, warpCursor: { _ in .success }),
            refreshStatus: {},
            overlay: overlay,
            makeOverlay: { overlay }
        )
    }
}
