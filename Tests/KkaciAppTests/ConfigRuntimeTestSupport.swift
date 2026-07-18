@testable import KkaciApp
import KkaciCore

final class ConfigStoreSpy: KkaciConfigStore {
    let loadedConfig: KkaciConfig
    let loadError: Error?
    let saveError: Error?
    private(set) var savedConfigs: [KkaciConfig] = []

    init(loadedConfig: KkaciConfig, loadError: Error? = nil, saveError: Error? = nil) {
        self.loadedConfig = loadedConfig
        self.loadError = loadError
        self.saveError = saveError
    }

    func load() throws -> KkaciConfig {
        if let loadError {
            throw loadError
        }
        return loadedConfig
    }

    func save(_ config: KkaciConfig) throws {
        if let saveError {
            throw saveError
        }
        savedConfigs.append(config)
    }
}

final class NoopShortcutActions: KeyboardShortcutActionHandling {
    func stepWorkspaceSwitcher(direction _: SwitcherDirection) {}
    func commitWorkspaceSwitcher() {}
    func stepWindowSwitcher(direction _: SwitcherDirection, wraps _: Bool) {}
    func commitWindowSwitcher() {}
    func cancelSwitcher() {}
    func switchWorkspace(to _: WorkspaceID) {}
    func moveFocusedWindow(to _: WorkspaceID) {}
}

func makeRuntime(
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

func config(key: String, workspace: String) -> KkaciConfig {
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

enum ConfigRuntimeTestError: Error, Equatable {
    case configSave
    case shortcutInstall
    case configApply
    case shortcutRollback
}

final class RuntimeConfigControllerSpy: RuntimeConfigControlling {
    var currentConfig: KkaciConfig
    private let applyError: Error?
    private(set) var appliedConfigs: [KkaciConfig] = []

    init(currentConfig: KkaciConfig, applyError: Error? = nil) {
        self.currentConfig = currentConfig
        self.applyError = applyError
    }

    func applyConfig(_ config: KkaciConfig) throws -> WorkspaceSyncSummary {
        appliedConfigs.append(config)
        if let applyError {
            throw applyError
        }
        currentConfig = config
        return WorkspaceSyncSummary(membershipChanges: [])
    }
}

final class ShortcutInstallerSpy: KeyboardShortcutInstalling {
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
