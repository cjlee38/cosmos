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
        guard case .invalid = runtime.status else {
            return XCTFail("Expected invalid config status")
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
        let runtime = makeRuntime(
            loadedConfig: previousConfig,
            controller: controller,
            shortcutInstaller: shortcutInstaller
        )
        try runtime.installInitialShortcuts(actions: NoopShortcutActions())

        try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())

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

        XCTAssertThrowsError(
            try runtime.updateConfig(updatedConfig, actions: NoopShortcutActions())
        ) { error in
            XCTAssertEqual(error as? TestError, .configApply)
        }
        XCTAssertEqual(shortcutInstaller.replacedKeys, [updatedConfig.bindings.map(\.key), []])
        XCTAssertEqual(controller.currentConfig, previousConfig)
    }

    func testMonitorUpdateDelegatesToCoreWithoutSavingInConfigRuntime() throws {
        let store = ConfigStoreSpy(loadedConfig: .default)
        let controller = RuntimeConfigControllerSpy(currentConfig: .default)
        let runtime = ConfigRuntime(
            configStore: store,
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: ShortcutInstallerSpy(),
            keyboardBindingMapper: KeyboardBindingMapper()
        )

        try runtime.updateWorkspaceMonitor("2", monitorSlot: 3)

        XCTAssertEqual(controller.monitorUpdates.count, 1)
        XCTAssertEqual(controller.monitorUpdates.first?.workspace, "2")
        XCTAssertEqual(controller.monitorUpdates.first?.monitorSlot, 3)
        XCTAssertTrue(store.savedConfigs.isEmpty)
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

    private func makeRuntime(
        loadedConfig: KkaciConfig,
        controller: RuntimeConfigControllerSpy,
        shortcutInstaller: ShortcutInstallerSpy
    ) -> ConfigRuntime {
        ConfigRuntime(
            configStore: ConfigStoreSpy(loadedConfig: loadedConfig),
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
}

private enum TestError: Error, Equatable {
    case shortcutInstall
    case configApply
    case shortcutRollback
}

private final class RuntimeConfigControllerSpy: RuntimeConfigControlling {
    var currentConfig: KkaciConfig
    private let applyError: Error?
    private(set) var appliedConfigs: [KkaciConfig] = []
    private(set) var monitorUpdates: [(workspace: String, monitorSlot: MonitorSlot)] = []

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

    func updateConfig(_ config: KkaciConfig) throws -> WorkspaceSyncSummary {
        try applyConfig(config, enablePersistence: true)
    }

    func updateWorkspaceMonitor(
        _ workspace: String,
        monitorSlot: MonitorSlot
    ) throws -> WorkspaceSyncSummary {
        monitorUpdates.append((workspace, monitorSlot))
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
    }
}

private final class ConfigStoreSpy: KkaciConfigStore {
    let loadedConfig: KkaciConfig
    private(set) var savedConfigs: [KkaciConfig] = []

    init(loadedConfig: KkaciConfig) {
        self.loadedConfig = loadedConfig
    }

    func load() throws -> KkaciConfig {
        loadedConfig
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
