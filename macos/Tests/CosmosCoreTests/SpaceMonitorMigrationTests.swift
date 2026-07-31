@testable import CosmosCore
import XCTest

final class SpaceMonitorMigrationTests: SpaceControllerTestCase {
    func testMonitorUpdateMovesSpaceWindowsToTheConfiguredMonitor() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemorySpaceConfigStore()
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)

        try controller.applyConfig(
            controller.currentConfig.assigningSpace(XCTUnwrap(SpaceID(rawValue: "1")), toMonitorSlot: 2)
        )

        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1100, y: 100, width: 300, height: 200))
        XCTAssertEqual(controller.spaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 2)
    }

    func testReassigningHiddenWindowToAnotherMonitorReplacesItsRestoreFrame() throws {
        let initialConfig = CosmosConfig(
            spaces: spaceConfigs(["1", "2", "A", "B"], displays: ["A": 2, "B": 2]),
            switcher: CosmosConfig.default.switcher
        )
        let store = InMemorySpaceConfigStore()
        try store.save(initialConfig)
        let sessionStateStore = InMemorySessionStateStore()
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 7, frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store,
            sessionStateStore: sessionStateStore
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(100, to: "B", controller: controller, windowSystem: windowSystem)

        XCTAssertEqual(
            sessionStateStore.records.first?.originalFrame,
            .frame(x: 1100, y: 100, width: 300, height: 200)
        )

        _ = try controller.switchSpace(to: "B")

        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1100, y: 100, width: 300, height: 200))
    }

    func testResizeFailureMovesCurrentSpaceWindowWithItsOriginalSize() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let store = InMemorySpaceConfigStore()
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider(),
            configStore: store
        )
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])
        windowSystem.operationFailure = { operation in
            guard case .setFrame(100, _) = operation else {
                return nil
            }
            return FakeWindowSystemError.frameWrite(100)
        }

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)

        try controller.applyConfig(
            controller.currentConfig.assigningSpace(XCTUnwrap(SpaceID(rawValue: "1")), toMonitorSlot: 2)
        )

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 1050, y: 50, width: originalFrame.size.width, height: originalFrame.size.height)
        )
        XCTAssertEqual(controller.spaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 2)
        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertEqual(Set(controller.visibleSpaces), ["1", "2"])
    }

    func testAdjustedResizeIsAcceptedWhenTheWindowReachedTheTargetMonitor() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: differentSizedDisplayProvider()
        )
        windowSystem.appliedFrame = { _, requested in
            WindowFrame(
                origin: requested.origin,
                size: CGSize(width: requested.size.width - 10, height: requested.size.height - 10)
            )
        }

        _ = try controller.handleWindowSetChanged()
        try controller.applyConfig(
            controller.currentConfig.assigningSpace(XCTUnwrap(SpaceID(rawValue: "1")), toMonitorSlot: 2)
        )

        XCTAssertEqual(windowSystem.frames[100], .frame(x: 1050, y: 50, width: 140, height: 90))
        XCTAssertEqual(controller.spaceFrame(for: 100), windowSystem.frames[100])
        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 2)
    }

    func testMonitorUpdateDoesNotCommitWhenResultingFrameIsUnavailable() throws {
        let originalFrame = WindowFrame.frame(x: 100, y: 100, width: 300, height: 200)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", frame: originalFrame)
        ])
        let store = InMemorySpaceConfigStore()
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        windowSystem.unavailableFrameReads.insert(100)

        XCTAssertThrowsError(try controller.applyConfig(
            controller.currentConfig.assigningSpace(XCTUnwrap(SpaceID(rawValue: "1")), toMonitorSlot: 2)
        ))

        XCTAssertEqual(configuredMonitorSlot(for: "1", in: controller), 1)
        XCTAssertEqual(controller.spaceFrame(for: 100), originalFrame)
        XCTAssertEqual(windowSystem.frames[100], originalFrame)
    }

    func testFailedHiddenWindowReassignmentRestoresThePreviousDurableFrame() throws {
        let initialConfig = CosmosConfig(
            spaces: spaceConfigs(["1", "2", "B"], displays: ["B": 2]),
            switcher: CosmosConfig.default.switcher
        )
        let store = InMemorySpaceConfigStore()
        try store.save(initialConfig)
        let sessionStateStore = InMemorySessionStateStore()
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Window", pid: 7, frame: .frame(x: 100, y: 100, width: 300, height: 200))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store,
            sessionStateStore: sessionStateStore
        )
        let originalFrame = try XCTUnwrap(windowSystem.frames[100])

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)
        var failedTargetWrite = false
        windowSystem.operationFailure = { operation in
            guard case .setPosition(100, _) = operation, !failedTargetWrite else {
                return nil
            }
            failedTargetWrite = true
            return FakeWindowSystemError.frameWrite(100)
        }

        XCTAssertThrowsError(try moveWindow(100, to: "B", controller: controller, windowSystem: windowSystem))

        XCTAssertEqual(controller.membership(for: 100), "2")
        XCTAssertEqual(controller.spaceFrame(for: 100), originalFrame)
        XCTAssertEqual(sessionStateStore.records.first?.space, "2")
        XCTAssertEqual(sessionStateStore.records.first?.originalFrame, originalFrame)
    }
}
