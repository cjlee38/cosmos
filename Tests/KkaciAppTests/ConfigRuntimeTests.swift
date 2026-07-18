@testable import KkaciApp
import KkaciCore
import XCTest

final class ConfigRuntimeTests: XCTestCase {
    func testReloadDoesNotApplyCoreConfigWhenShortcutReplacementFails() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let loadedConfig = config(key: "option+2", workspace: "2")
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let shortcutInstaller = ShortcutInstallerSpy(failuresByCall: [1: ConfigRuntimeTestError.shortcutInstall])
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions())) { error in
            XCTAssertEqual(error as? ConfigRuntimeTestError, .shortcutInstall)
        }
        XCTAssertTrue(controller.appliedConfigs.isEmpty)
        XCTAssertEqual(controller.currentConfig, previousConfig)
        guard case .runtimeError = runtime.status else {
            return XCTFail("Expected runtime error status")
        }
    }

    func testReloadRestoresPreviousShortcutsWhenCoreApplyFails() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let loadedConfig = config(key: "option+2", workspace: "2")
        let controller = RuntimeConfigControllerSpy(
            currentConfig: previousConfig,
            applyError: ConfigRuntimeTestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions())) { error in
            XCTAssertEqual(error as? ConfigRuntimeTestError, .configApply)
        }
        XCTAssertEqual(shortcutInstaller.replacedKeys, [["option+1"], ["option+2"], ["option+1"]])
        XCTAssertEqual(controller.currentConfig, previousConfig)
    }

    func testReloadReportsCoreAndShortcutRollbackFailures() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let loadedConfig = config(key: "option+2", workspace: "2")
        let controller = RuntimeConfigControllerSpy(
            currentConfig: previousConfig,
            applyError: ConfigRuntimeTestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy(failuresByCall: [2: ConfigRuntimeTestError.shortcutRollback])
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions())) { error in
            guard let transactionError = error as? ConfigReloadTransactionError else {
                return XCTFail("Expected ConfigReloadTransactionError, got \(error)")
            }
            XCTAssertEqual(transactionError.applyError as? ConfigRuntimeTestError, .configApply)
            XCTAssertEqual(transactionError.rollbackError as? ConfigRuntimeTestError, .shortcutRollback)
        }
    }

    func testSuccessfulReloadInstallsShortcutsAndAppliesCoreConfig() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let loadedConfig = config(key: "option+2", workspace: "2")
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        try runtime.reload(actions: NoopShortcutActions())

        XCTAssertEqual(shortcutInstaller.replacedKeys, [["option+2"]])
        XCTAssertEqual(controller.appliedConfigs, [loadedConfig])
        XCTAssertEqual(controller.currentConfig, loadedConfig)
        XCTAssertEqual(runtime.status, .valid)
    }

    func testSettingsConfigUpdateInstallsShortcutsAndUpdatesCoreConfig() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let updatedConfig = try XCTUnwrap(previousConfig.addingWorkspace("A"))
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let shortcutInstaller = ShortcutInstallerSpy()
        let configStore = ConfigStoreSpy(loadedConfig: previousConfig)
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller,
            configStore: configStore
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        let result = try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())

        XCTAssertEqual(result, .applied)
        XCTAssertEqual(configStore.savedConfigs, [updatedConfig])
        XCTAssertEqual(controller.currentConfig, updatedConfig)
        XCTAssertEqual(shortcutInstaller.replacedKeys.last, updatedConfig.configuredShortcuts.map(\.key))
    }

    func testSettingsConfigSaveFailureLeavesRuntimeAndShortcutsUnchanged() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let updatedConfig = try XCTUnwrap(previousConfig.addingWorkspace("A"))
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let shortcutInstaller = ShortcutInstallerSpy()
        let configStore = ConfigStoreSpy(
            loadedConfig: previousConfig,
            saveError: ConfigRuntimeTestError.configSave
        )
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller,
            configStore: configStore
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        XCTAssertThrowsError(
            try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())
        ) { error in
            XCTAssertEqual(error as? ConfigRuntimeTestError, .configSave)
        }
        XCTAssertEqual(runtime.desiredConfig, previousConfig)
        XCTAssertEqual(controller.currentConfig, previousConfig)
        XCTAssertEqual(shortcutInstaller.replacedKeys, [["option+1"]])
    }

    func testSettingsConfigUpdateRestoresPreviousShortcutsWhenCoreUpdateFails() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let updatedConfig = try XCTUnwrap(previousConfig.addingWorkspace("A"))
        let controller = RuntimeConfigControllerSpy(
            currentConfig: previousConfig,
            applyError: ConfigRuntimeTestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        let result = try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())

        XCTAssertEqual(result, .rejected("configApply"))
        XCTAssertEqual(shortcutInstaller.replacedKeys, [updatedConfig.configuredShortcuts.map(\.key), []])
        XCTAssertEqual(controller.currentConfig, previousConfig)
        XCTAssertEqual(runtime.desiredConfig, updatedConfig)
        guard case .runtimeError = runtime.status else {
            return XCTFail("Expected runtime error status")
        }
    }

    func testShortcutRecordingTemporarilyUnregistersAndCancelRestoresShortcuts() throws {
        let config = config(key: "option+1", workspace: "1")
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = makeRuntime(
            loadedConfig: config,
            controller: RuntimeConfigControllerSpy(currentConfig: config),
            shortcutInstaller: shortcutInstaller
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        try runtime.beginShortcutRecording()
        try runtime.cancelShortcutRecording()

        XCTAssertEqual(shortcutInstaller.replacedKeys, [["option+1"], [], ["option+1"]])
    }

    func testShortcutRecordingCanRetryCancelAfterRestoreFails() throws {
        let config = config(key: "option+1", workspace: "1")
        let shortcutInstaller = ShortcutInstallerSpy(
            failuresByCall: [3: ConfigRuntimeTestError.shortcutRollback]
        )
        let runtime = makeRuntime(
            loadedConfig: config,
            controller: RuntimeConfigControllerSpy(currentConfig: config),
            shortcutInstaller: shortcutInstaller
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())
        try runtime.beginShortcutRecording()

        XCTAssertThrowsError(try runtime.cancelShortcutRecording()) { error in
            XCTAssertEqual(error as? ConfigRuntimeTestError, .shortcutRollback)
        }
        guard case .runtimeError = runtime.status else {
            return XCTFail("Expected runtime error status")
        }

        try runtime.cancelShortcutRecording()

        XCTAssertEqual(shortcutInstaller.replacedKeys, [
            ["option+1"],
            [],
            ["option+1"],
            ["option+1"]
        ])
    }

    func testSuccessfulShortcutUpdateFinishesRecordingWithUpdatedShortcuts() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let updatedConfig = config(key: "option+2", workspace: "2")
        let shortcutInstaller = ShortcutInstallerSpy()
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        try runtime.beginShortcutRecording()
        try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())
        try runtime.cancelShortcutRecording()

        XCTAssertEqual(shortcutInstaller.replacedKeys, [["option+1"], [], ["option+2"]])
        XCTAssertEqual(controller.currentConfig, updatedConfig)
    }
}
