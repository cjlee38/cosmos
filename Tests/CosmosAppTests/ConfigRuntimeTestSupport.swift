@testable import CosmosApp
import CosmosCore

final class ConfigStoreSpy: CosmosConfigStore {
    let loadedConfig: CosmosConfig
    let loadError: Error?
    let saveError: Error?
    private(set) var savedConfigs: [CosmosConfig] = []

    init(loadedConfig: CosmosConfig, loadError: Error? = nil, saveError: Error? = nil) {
        self.loadedConfig = loadedConfig
        self.loadError = loadError
        self.saveError = saveError
    }

    func load() throws -> CosmosConfig {
        if let loadError {
            throw loadError
        }
        return loadedConfig
    }

    func save(_ config: CosmosConfig) throws {
        if let saveError {
            throw saveError
        }
        savedConfigs.append(config)
    }
}

final class NoopShortcutActions: KeyboardShortcutActionHandling {
    func stepSpaceSwitcher(direction _: SwitcherDirection) {}
    func commitSpaceSwitcher() {}
    func stepWindowSwitcher(direction _: SwitcherDirection, wraps _: Bool) {}
    func commitWindowSwitcher() {}
    func cancelSwitcher() {}
    func switchSpace(to _: SpaceID) {}
    func moveFocusedWindow(to _: SpaceID) {}
    func centerFocusedWindow() {}
}

func makeRuntime(
    loadedConfig: CosmosConfig,
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

func config(key: String, space: String) -> CosmosConfig {
    CosmosConfig(
        spaces: ["1", "2"].map { name in
            let id = SpaceID(rawValue: name)!
            return SpaceConfig(
                id: id,
                shortcuts: SpaceShortcutConfig(
                    switchSpace: name == space ? key : nil
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
    var currentConfig: CosmosConfig
    private let applyError: Error?
    private(set) var appliedConfigs: [CosmosConfig] = []

    init(currentConfig: CosmosConfig, applyError: Error? = nil) {
        self.currentConfig = currentConfig
        self.applyError = applyError
    }

    func applyConfig(_ config: CosmosConfig) throws -> SpaceSyncSummary {
        appliedConfigs.append(config)
        if let applyError {
            throw applyError
        }
        currentConfig = config
        return SpaceSyncSummary(membershipChanges: [])
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
