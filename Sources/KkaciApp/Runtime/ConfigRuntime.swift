import Foundation
import KkaciCore

protocol RuntimeConfigControlling: AnyObject {
    var currentConfig: KkaciConfig { get }

    @discardableResult
    func applyConfig(_ config: KkaciConfig, enablePersistence: Bool) throws -> WorkspaceSyncSummary

    @discardableResult
    func updateConfig(_ config: KkaciConfig) throws -> WorkspaceSyncSummary

    @discardableResult
    func updateWorkspaceMonitor(_ workspace: String, monitorSlot: MonitorSlot) throws -> WorkspaceSyncSummary
}

extension WorkspaceController: RuntimeConfigControlling {}

protocol KeyboardShortcutInstalling: AnyObject {
    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws
}

extension KeyboardShortcutManager: KeyboardShortcutInstalling {}

enum ConfigRuntimeStatus: Equatable {
    case valid
    case invalid(String)
}

final class ConfigRuntime {
    let configURL: URL?
    private(set) var status: ConfigRuntimeStatus
    private let configStore: any KkaciConfigStore
    private let controller: any RuntimeConfigControlling
    private let shortcutInstaller: any KeyboardShortcutInstalling
    private let keyboardBindingMapper: KeyboardBindingMapper
    private var installedRegistrations: [KeyboardShortcutRegistration] = []

    init(
        configStore: any KkaciConfigStore,
        configURL: URL?,
        controller: any RuntimeConfigControlling,
        keyboardShortcutManager: any KeyboardShortcutInstalling,
        keyboardBindingMapper: KeyboardBindingMapper,
        initialLoadError: Error? = nil
    ) {
        self.configStore = configStore
        self.configURL = configURL
        self.controller = controller
        shortcutInstaller = keyboardShortcutManager
        self.keyboardBindingMapper = keyboardBindingMapper
        status = initialLoadError.map { .invalid(String(describing: $0)) } ?? .valid
    }

    func installInitialShortcuts(actions: any KeyboardShortcutActionHandling) throws {
        do {
            let registrations = try registrations(for: controller.currentConfig.bindings, actions: actions)
            try shortcutInstaller.replaceShortcuts(registrations)
            installedRegistrations = registrations
        } catch {
            status = .invalid(String(describing: error))
            throw error
        }
    }

    func reload(actions: any KeyboardShortcutActionHandling) throws {
        do {
            try performReload(actions: actions)
            status = .valid
        } catch {
            status = .invalid(String(describing: error))
            throw error
        }
    }

    private func performReload(actions: any KeyboardShortcutActionHandling) throws {
        let loadedConfig = try configStore.load()
        try applyConfigWithShortcuts(loadedConfig, actions: actions) { config in
            try controller.applyConfig(config, enablePersistence: true)
        }
    }

    func updateConfig(
        _ config: KkaciConfig,
        actions: any KeyboardShortcutActionHandling
    ) throws {
        try applyConfigWithShortcuts(config, actions: actions) { config in
            try controller.updateConfig(config)
        }
    }

    private func applyConfigWithShortcuts(
        _ config: KkaciConfig,
        actions: any KeyboardShortcutActionHandling,
        apply: (KkaciConfig) throws -> Void
    ) throws {
        let previousRegistrations = installedRegistrations
        let updatedRegistrations = try registrations(for: config.bindings, actions: actions)

        try shortcutInstaller.replaceShortcuts(updatedRegistrations)
        installedRegistrations = updatedRegistrations
        do {
            try apply(config)
        } catch let applyError {
            do {
                try shortcutInstaller.replaceShortcuts(previousRegistrations)
                installedRegistrations = previousRegistrations
            } catch let rollbackError {
                throw ConfigReloadTransactionError(
                    applyError: applyError,
                    rollbackError: rollbackError
                )
            }
            throw applyError
        }
    }

    func updateWorkspaceMonitor(_ workspace: String, monitorSlot: MonitorSlot) throws {
        try controller.updateWorkspaceMonitor(workspace, monitorSlot: monitorSlot)
    }

    private func registrations(
        for bindings: [HotKeyBinding],
        actions: any KeyboardShortcutActionHandling
    ) throws -> [KeyboardShortcutRegistration] {
        try keyboardBindingMapper.registrations(for: bindings, actions: actions)
    }
}

struct ConfigReloadTransactionError: Error, CustomStringConvertible {
    let applyError: Error
    let rollbackError: Error

    var description: String {
        "Config apply failed: \(applyError); shortcut rollback failed: \(rollbackError)"
    }
}
