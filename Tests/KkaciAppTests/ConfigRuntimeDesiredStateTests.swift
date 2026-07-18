@testable import KkaciApp
import KkaciCore
import XCTest

final class ConfigRuntimeDesiredStateTests: XCTestCase {
    func testInvalidShortcutUpdateFinishesRecordingAndRestoresPreviousShortcuts() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let withWorkspace = try XCTUnwrap(previousConfig.addingWorkspace("A"))
        let invalidConfig = try XCTUnwrap(withWorkspace.updatingShortcut(
            "option+1",
            for: .switchWorkspace("A")
        ))
        let shortcutInstaller = ShortcutInstallerSpy()
        let configStore = ConfigStoreSpy(loadedConfig: previousConfig)
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: RuntimeConfigControllerSpy(currentConfig: previousConfig),
            shortcutInstaller: shortcutInstaller,
            configStore: configStore
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())
        try runtime.beginShortcutRecording()

        let result = try runtime.updateConfig(invalidConfig, actions: NoopShortcutActions())
        try runtime.cancelShortcutRecording()

        guard case .rejected = result else {
            return XCTFail("Expected rejected config result")
        }
        XCTAssertEqual(shortcutInstaller.replacedKeys, [
            ["option+1"],
            [],
            ["option+1", "option+1", "option+shift+a"],
            ["option+1"]
        ])
        XCTAssertEqual(configStore.savedConfigs, [invalidConfig])
        XCTAssertEqual(runtime.desiredConfig, invalidConfig)
        XCTAssertEqual(runtime.shortcutValidationMessages[.switchWorkspace("1")],
                       "Already assigned to \"Switch to Workspace A\".")
        XCTAssertEqual(runtime.shortcutValidationMessages[.switchWorkspace("A")],
                       "Already assigned to \"Switch to Workspace 1\".")
    }

    func testInitialShortcutConflictKeepsDesiredConfigAndFallsBackToDefaults() throws {
        let invalidConfig = try XCTUnwrap(
            KkaciConfig.default.updatingShortcut("option+1", for: .switchWorkspace("2"))
        )
        let controller = RuntimeConfigControllerSpy(currentConfig: invalidConfig)
        let runtime = ConfigRuntime(
            configStore: ConfigStoreSpy(loadedConfig: invalidConfig),
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: ShortcutInstallerSpy(),
            keyboardBindingMapper: KeyboardBindingMapper()
        )

        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        XCTAssertEqual(runtime.desiredConfig, invalidConfig)
        XCTAssertEqual(controller.currentConfig, .default)
        XCTAssertTrue(runtime.isSettingsEditable)
        guard case .invalid = runtime.status else {
            return XCTFail("Expected invalid config status")
        }
    }

    func testInitialFallbackRestoresShortcutStateWhenCoreFallbackFails() throws {
        let invalidConfig = try XCTUnwrap(
            KkaciConfig.default.updatingShortcut("option+1", for: .switchWorkspace("2"))
        )
        let controller = RuntimeConfigControllerSpy(
            currentConfig: invalidConfig,
            applyError: ConfigRuntimeTestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = ConfigRuntime(
            configStore: ConfigStoreSpy(loadedConfig: invalidConfig),
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: shortcutInstaller,
            keyboardBindingMapper: KeyboardBindingMapper()
        )

        XCTAssertThrowsError(try runtime.installInitialShortcuts(actions: NoopShortcutActions())) { error in
            XCTAssertEqual(error as? ConfigRuntimeTestError, .configApply)
        }
        XCTAssertEqual(
            shortcutInstaller.replacedKeys,
            [
                invalidConfig.configuredShortcuts.map(\.key),
                KkaciConfig.default.configuredShortcuts.map(\.key),
                []
            ]
        )
        XCTAssertEqual(controller.currentConfig, invalidConfig)
    }

    func testInitialCarbonRegistrationFailureKeepsLoadedWorkspaceConfig() throws {
        let config = config(key: "option+1", workspace: "2")
        let controller = RuntimeConfigControllerSpy(currentConfig: config)
        let shortcutInstaller = ShortcutInstallerSpy(
            failuresByCall: [1: ConfigRuntimeTestError.shortcutInstall]
        )
        let runtime = makeRuntime(
            loadedConfig: config,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        XCTAssertThrowsError(try runtime.installInitialShortcuts(actions: NoopShortcutActions())) { error in
            XCTAssertEqual(error as? ConfigRuntimeTestError, .shortcutInstall)
        }
        XCTAssertEqual(controller.currentConfig, config)
        XCTAssertTrue(controller.appliedConfigs.isEmpty)
        guard case .runtimeError = runtime.status else {
            return XCTFail("Expected runtime error status")
        }
    }

    func testReloadedShortcutConflictKeepsDesiredConfigAndPreviousRuntimeConfig() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let withWorkspace = try XCTUnwrap(previousConfig.addingWorkspace("A"))
        let invalidConfig = try XCTUnwrap(withWorkspace.updatingShortcut(
            "option+1",
            for: .switchWorkspace("A")
        ))
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let runtime = makeRuntime(
            loadedConfig: invalidConfig,
            controller: controller,
            shortcutInstaller: ShortcutInstallerSpy()
        )

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions()))

        XCTAssertEqual(runtime.desiredConfig, invalidConfig)
        XCTAssertEqual(controller.currentConfig, previousConfig)
        XCTAssertEqual(runtime.shortcutValidationMessages[.switchWorkspace("1")],
                       "Already assigned to \"Switch to Workspace A\".")
        XCTAssertEqual(runtime.shortcutValidationMessages[.switchWorkspace("A")],
                       "Already assigned to \"Switch to Workspace 1\".")
    }

    func testReloadFailureMakesSettingsReadOnlyAndKeepsAppliedConfig() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let store = ConfigStoreSpy(
            loadedConfig: previousConfig,
            loadError: NSError(domain: "ConfigRuntimeDesiredStateTests", code: 1)
        )
        let runtime = ConfigRuntime(
            configStore: store,
            configURL: nil,
            controller: RuntimeConfigControllerSpy(currentConfig: previousConfig),
            keyboardShortcutManager: ShortcutInstallerSpy(),
            keyboardBindingMapper: KeyboardBindingMapper()
        )

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions()))

        XCTAssertNil(runtime.desiredConfig)
        XCTAssertFalse(runtime.isSettingsEditable)
        XCTAssertEqual(runtime.settingsConfig, previousConfig)
    }

    func testInitialLoadErrorStartsWithInvalidStatus() {
        let runtime = ConfigRuntime(
            configStore: ConfigStoreSpy(loadedConfig: .default),
            configURL: nil,
            controller: RuntimeConfigControllerSpy(currentConfig: .default),
            keyboardShortcutManager: ShortcutInstallerSpy(),
            keyboardBindingMapper: KeyboardBindingMapper(),
            initialLoadError: ConfigRuntimeTestError.configApply
        )

        XCTAssertNoThrow(try runtime.installInitialShortcuts(actions: NoopShortcutActions()))
        guard case let .invalid(message) = runtime.status else {
            return XCTFail("Expected invalid config status")
        }
        XCTAssertTrue(message.contains("configApply"))
    }
}
