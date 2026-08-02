@testable import CosmosApp
import CosmosCore
import XCTest

final class WindowRuntimeScreenLockTests: XCTestCase {
    func testScreenUnlockPreservesWindowsMissingDuringLock() throws {
        let visibleWindow = makeSwitcherTestWindow(id: 100, title: "Visible")
        let hiddenWindow = makeSwitcherTestWindow(id: 200, title: "Hidden")
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            visibleWindow,
            hiddenWindow
        ])
        try moveSwitcherTestWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        let handler = makeHandler(controller: controller)
        windowSystem.resetDiscoveryModes()

        handler.screenLockChanged(isLocked: true)
        windowSystem.replaceWindows([])
        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))

        XCTAssertTrue(windowSystem.discoveryModes.isEmpty)

        handler.screenLockChanged(isLocked: false)

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.membership(for: 200), "2")
        XCTAssertTrue(controller.isHiddenBySpace(200))
        XCTAssertEqual(windowSystem.discoveryModes, [.sessionRecovery])
    }

    func testScreenUnlockWaitsForSystemWakeBeforeRecovering() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "Window")
        ])
        let handler = makeHandler(controller: controller)
        windowSystem.resetDiscoveryModes()

        handler.screenLockChanged(isLocked: true)
        handler.systemSleepChanged(isAwake: false)
        handler.screenLockChanged(isLocked: false)

        XCTAssertTrue(windowSystem.discoveryModes.isEmpty)

        handler.systemSleepChanged(isAwake: true)

        XCTAssertEqual(windowSystem.discoveryModes, [.sessionRecovery])
        XCTAssertFalse(handler.hasPendingContinuityRecovery)
    }

    func testDiscoveryStartedBeforeScreenLockCannotRemoveMembership() throws {
        let window = makeSwitcherTestWindow(id: 100, title: "Window")
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [window])
        var scheduledDiscoveries: [() -> Void] = []
        let handler = makeHandler(
            controller: controller,
            scheduleDiscovery: { scheduledDiscoveries.append($0) }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))
        handler.screenLockChanged(isLocked: true)
        windowSystem.replaceWindows([])
        scheduledDiscoveries.removeFirst()()

        XCTAssertEqual(controller.membership(for: 100), "1")

        windowSystem.replaceWindows([window])
        handler.screenLockChanged(isLocked: false)
        scheduledDiscoveries.removeFirst()()

        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertFalse(handler.hasPendingContinuityRecovery)
    }

    func testScreenUnlockWaitsForDisplayReconfigurationToEnd() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "Window")
        ])
        let handler = makeHandler(controller: controller)
        windowSystem.resetDiscoveryModes()

        handler.screenLockChanged(isLocked: true)
        handler.displayReconfigurationBegan()
        handler.screenLockChanged(isLocked: false)

        XCTAssertTrue(windowSystem.discoveryModes.isEmpty)

        handler.displayReconfigurationEnded()

        XCTAssertEqual(windowSystem.discoveryModes, [.sessionRecovery])
        XCTAssertFalse(handler.hasPendingContinuityRecovery)
    }

    func testBufferedDisplayChangeWaitsForDisplayReconfigurationToEnd() throws {
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [
            makeSwitcherTestWindow(id: 100, title: "Window")
        ])
        let handler = makeHandler(controller: controller)
        windowSystem.resetDiscoveryModes()

        handler.screenLockChanged(isLocked: true)
        handler.displayReconfigurationBegan()
        handler.screenLockChanged(isLocked: false)
        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .displayChanged, windowID: nil)
        ]))

        XCTAssertTrue(windowSystem.discoveryModes.isEmpty)

        handler.displayReconfigurationEnded()

        XCTAssertEqual(windowSystem.discoveryModes.first, .sessionRecovery)
        XCTAssertFalse(handler.hasPendingContinuityRecovery)
    }

    private func makeHandler(
        controller: SpaceController,
        scheduleDiscovery: @escaping (@escaping () -> Void) -> Void = { $0() }
    ) -> WindowRuntimeEventHandler {
        WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: scheduleDiscovery,
            scheduleApply: { $0() }
        )
    }
}
