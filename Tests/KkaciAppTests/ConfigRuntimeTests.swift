@testable import KkaciApp
import KkaciCore
import XCTest

final class ConfigRuntimeTests: XCTestCase {
    func testReloadDoesNotApplyCoreConfigWhenShortcutReplacementFails() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let loadedConfig = config(key: "option+2", workspace: "2")
        let controller = RuntimeConfigControllerSpy(currentConfig: previousConfig)
        let shortcutInstaller = ShortcutInstallerSpy(failuresByCall: [1: TestError.shortcutInstall])
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions())) { error in
            XCTAssertEqual(error as? TestError, .shortcutInstall)
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
            applyError: TestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions())) { error in
            XCTAssertEqual(error as? TestError, .configApply)
        }
        XCTAssertEqual(shortcutInstaller.replacedKeys, [["option+1"], ["option+2"], ["option+1"]])
        XCTAssertEqual(controller.currentConfig, previousConfig)
    }

    func testReloadReportsCoreAndShortcutRollbackFailures() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let loadedConfig = config(key: "option+2", workspace: "2")
        let controller = RuntimeConfigControllerSpy(
            currentConfig: previousConfig,
            applyError: TestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy(failuresByCall: [2: TestError.shortcutRollback])
        let runtime = makeRuntime(
            loadedConfig: loadedConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        XCTAssertThrowsError(try runtime.reload(actions: NoopShortcutActions())) { error in
            guard let transactionError = error as? ConfigReloadTransactionError else {
                return XCTFail("Expected ConfigReloadTransactionError, got \(error)")
            }
            XCTAssertEqual(transactionError.applyError as? TestError, .configApply)
            XCTAssertEqual(transactionError.rollbackError as? TestError, .shortcutRollback)
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
        XCTAssertEqual(shortcutInstaller.replacedKeys.last, updatedConfig.bindings.map(\.key))
    }

    func testSettingsConfigUpdateRestoresPreviousShortcutsWhenCoreUpdateFails() throws {
        let previousConfig = config(key: "option+1", workspace: "1")
        let updatedConfig = try XCTUnwrap(previousConfig.addingWorkspace("A"))
        let controller = RuntimeConfigControllerSpy(
            currentConfig: previousConfig,
            applyError: TestError.configApply
        )
        let shortcutInstaller = ShortcutInstallerSpy()
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )

        let result = try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())

        XCTAssertEqual(result, .rejected("configApply"))
        XCTAssertEqual(shortcutInstaller.replacedKeys, [updatedConfig.bindings.map(\.key), []])
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

final class ConfigRuntimeDesiredStateTests: XCTestCase {
    func testInvalidShortcutUpdateKeepsRecordingUntilCancelRestoresPreviousShortcuts() throws {
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
        let store = ConfigStoreSpy(loadedConfig: previousConfig, loadError: TestError.configLoad)
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
            initialLoadError: TestError.configApply
        )

        XCTAssertNoThrow(try runtime.installInitialShortcuts(actions: NoopShortcutActions()))
        guard case let .invalid(message) = runtime.status else {
            return XCTFail("Expected invalid config status")
        }
        XCTAssertTrue(message.contains("configApply"))
    }
}

private func makeRuntime(
    loadedConfig: KkaciConfig,
    controller: RuntimeConfigControllerSpy,
    shortcutInstaller: ShortcutInstallerSpy,
    configStore: ConfigStoreSpy? = nil
) -> ConfigRuntime {
    ConfigRuntime(
        configStore: configStore ?? ConfigStoreSpy(loadedConfig: loadedConfig),
        configURL: nil,
        controller: controller,
        keyboardShortcutManager: shortcutInstaller,
        keyboardBindingMapper: KeyboardBindingMapper()
    )
}

private func config(key: String, workspace: String) -> KkaciConfig {
    KkaciConfig(
        workspaces: ["1", "2"].map { name in
            let id = WorkspaceID(rawValue: name)!
            return WorkspaceConfig(
                id: id,
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: name == workspace ? key : nil
                )
            )
        }
    )
}

private enum TestError: Error, Equatable {
    case configLoad
    case shortcutInstall
    case configApply
    case shortcutRollback
}

private final class RuntimeConfigControllerSpy: RuntimeConfigControlling {
    var currentConfig: KkaciConfig
    private let applyError: Error?
    private(set) var appliedConfigs: [KkaciConfig] = []

    init(currentConfig: KkaciConfig, applyError: Error? = nil) {
        self.currentConfig = currentConfig
        self.applyError = applyError
    }

    func applyConfig(_ config: KkaciConfig, enablePersistence _: Bool) throws -> WorkspaceSyncSummary {
        appliedConfigs.append(config)
        if let applyError {
            throw applyError
        }
        currentConfig = config
        return WorkspaceSyncSummary(autoAssigned: [], removed: [])
    }
}

private final class ShortcutInstallerSpy: KeyboardShortcutInstalling {
    private let failuresByCall: [Int: Error]
    private(set) var replacedKeys: [[String]] = []

    init(failuresByCall: [Int: Error] = [:]) {
        self.failuresByCall = failuresByCall
    }

    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws {
        replacedKeys.append(registrations.map(\.key))
        if let error = failuresByCall[replacedKeys.count] {
            throw error
        }
        _ = try KeyboardShortcutResolver().resolve(registrations)
    }
}

private final class ConfigStoreSpy: KkaciConfigStore {
    let loadedConfig: KkaciConfig
    let loadError: Error?
    private(set) var savedConfigs: [KkaciConfig] = []

    init(loadedConfig: KkaciConfig, loadError: Error? = nil) {
        self.loadedConfig = loadedConfig
        self.loadError = loadError
    }

    func load() throws -> KkaciConfig {
        if let loadError {
            throw loadError
        }
        return loadedConfig
    }

    func save(_ config: KkaciConfig) throws {
        savedConfigs.append(config)
    }
}

private final class NoopShortcutActions: KeyboardShortcutActionHandling {
    func stepWorkspaceSwitcher(direction _: SwitcherDirection) {}
    func commitWorkspaceSwitcher() {}
    func stepWindowSwitcher(direction _: SwitcherDirection, wraps _: Bool) {}
    func commitWindowSwitcher() {}
    func switchWorkspace(named _: String) {}
    func moveFocusedWindow(to _: String) {}
}
