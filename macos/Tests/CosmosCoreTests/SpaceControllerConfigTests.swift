@testable import CosmosCore
import XCTest

final class SpaceControllerConfigTests: SpaceControllerTestCase {
    func testBootstrapUsesConfiguredCurrentSpaceWhenSpaceOneIsAbsent() throws {
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["A", "B"]),
            switcher: CosmosConfig.default.switcher
        ))
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "Window")])
        let controller = makeController(windowSystem, configStore: store)

        _ = try controller.bootstrapWindowState()

        XCTAssertEqual(controller.currentSpace, "A")
        XCTAssertEqual(controller.membership(for: 100), "A")
    }

    func testMissingSpaceAssignmentDoesNotApplyVisibility() throws {
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(100)

        let assigned = try moveWindow(100, to: "scratch", controller: controller, windowSystem: windowSystem)

        XCTAssertNil(assigned)
        XCTAssertFalse(controller.spaces.contains("scratch"))
        XCTAssertEqual(controller.spaces, ["1", "2", "3"])
        XCTAssertEqual(controller.membership(for: 100), "1")
    }

    func testMissingSpaceSwitchIsNoOp() throws {
        let windowSystem = FakeWindowSystem(windows: [.window(id: 100, title: "One")])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)

        let sync = try controller.switchSpace(to: "scratch")

        XCTAssertNil(sync)
        XCTAssertFalse(controller.spaces.contains("scratch"))
        XCTAssertEqual(controller.currentSpace, "1")
    }

    func testConfigVisibilityFailureRestoresPreviousConfigAndVisibility() throws {
        let initialConfig = CosmosConfig(
            spaces: spaceConfigs(["1", "2"], displays: ["2": 2]),
            switcher: CosmosConfig.default.switcher
        )
        let store = InMemorySpaceConfigStore()
        try store.save(initialConfig)
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "Main", frame: .frame(x: 100, y: 100)),
            .window(id: 200, title: "Secondary", frame: .frame(x: 1100, y: 100))
        ])
        let controller = makeController(
            windowSystem,
            displayProvider: twoDisplayProvider(),
            configStore: store
        )

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        windowSystem.frameWriteFailures.insert(200)

        XCTAssertThrowsError(try controller.applyConfig(configWithSwitchShortcut(
            "option+x",
            space: "1",
            spaceIDs: ["1", "2"]
        )))

        XCTAssertEqual(controller.currentConfig, initialConfig)
        XCTAssertEqual(configuredMonitorSlot(for: "2", in: controller), 2)
        XCTAssertFalse(controller.isHiddenBySpace(200))
    }

    func testConfigApplyReportsApplyAndRollbackFailures() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 200, title: "First"),
            .window(id: 201, title: "Second")
        ])
        let controller = makeController(windowSystem, displayProvider: twoDisplayProvider())

        _ = try controller.handleWindowSetChanged()
        try moveWindow(200, to: "2", controller: controller, windowSystem: windowSystem)
        try moveWindow(201, to: "2", controller: controller, windowSystem: windowSystem)

        var restoredWindowID: WindowID?
        windowSystem.operationFailure = { [hidePoint] operation in
            guard case let .setPosition(windowID, point) = operation else {
                return nil
            }
            if point != hidePoint {
                if restoredWindowID == nil {
                    restoredWindowID = windowID
                    return nil
                }
                return FakeWindowSystemError.frameWrite(windowID)
            }
            if windowID == restoredWindowID {
                return FakeWindowSystemError.frameWrite(windowID)
            }
            return nil
        }

        XCTAssertThrowsError(try controller.applyConfig(CosmosConfig(
            spaces: spaceConfigs(["1", "2"], displays: ["2": 2]),
            switcher: CosmosConfig.default.switcher
        ))) { error in
            guard let transactionError = error as? SpaceTransactionError else {
                return XCTFail("Expected SpaceTransactionError, got \(error)")
            }
            XCTAssertTrue(transactionError.applyError is FakeWindowSystemError)
            XCTAssertTrue(transactionError.rollbackError is FakeWindowSystemError)
        }
    }

    func testFailedStartupConfigLoadUsesDefaultsAndReportsTheError() {
        let windowSystem = FakeWindowSystem(windows: [])
        let store = FailingLoadSpaceConfigStore()
        let controller = makeController(windowSystem, configStore: store)

        XCTAssertEqual(controller.spaces, ["1", "2", "3"])
        XCTAssertEqual(controller.startupConfigLoadError as? FailingLoadSpaceConfigStore.Error, .loadFailed)
    }

    func testApplyConfigRemovesSpaceAndReassignsItsWindowToCurrentSpace() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One")
        ])
        let store = InMemorySpaceConfigStore()
        try store.save(CosmosConfig(
            spaces: spaceConfigs(["1", "2", "A"]),
            switcher: CosmosConfig.default.switcher
        ))
        let controller = makeController(windowSystem, configStore: store)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "A", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchSpace(to: "A")
        try controller.applyConfig(configWithSwitchShortcut(
            "option+d",
            space: "3",
            spaceIDs: ["1", "2", "3"]
        ))

        XCTAssertEqual(controller.spaces, ["1", "2", "3"])
        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertEqual(controller.membership(for: 100), "1")
        XCTAssertEqual(controller.currentConfig.configuredShortcuts, [
            ConfiguredShortcut(key: "option+command+c", target: .centerWindow),
            ConfiguredShortcut(key: "option+d", target: .switchSpace("3"))
        ])
    }
}

private func configWithSwitchShortcut(
    _ shortcut: String,
    space: String,
    spaceIDs: [String]
) -> CosmosConfig {
    CosmosConfig(
        spaces: spaceIDs.map { spaceID in
            let id = SpaceID(rawValue: spaceID)!
            return SpaceConfig(
                id: id,
                shortcuts: SpaceShortcutConfig(
                    switchSpace: id.rawValue == space ? shortcut : nil
                )
            )
        }
    )
}
