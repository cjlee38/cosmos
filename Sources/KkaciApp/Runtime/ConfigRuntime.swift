import Foundation
import KkaciCore

protocol RuntimeConfigControlling: AnyObject {
    var currentConfig: KkaciConfig { get }

    @discardableResult
    func applyConfig(_ config: KkaciConfig, enablePersistence: Bool) throws -> WorkspaceSyncSummary

    @discardableResult
    func updateWorkspaceMonitor(_ workspace: String, monitorSlot: MonitorSlot) throws -> WorkspaceSyncSummary
}

extension WorkspaceController: RuntimeConfigControlling {}

protocol KeyboardShortcutInstalling: AnyObject {
    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws
}

extension KeyboardShortcutManager: KeyboardShortcutInstalling {}

final class ConfigRuntime {
    let configURL: URL?
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
        keyboardBindingMapper: KeyboardBindingMapper
    ) {
        self.configStore = configStore
        self.configURL = configURL
        self.controller = controller
        shortcutInstaller = keyboardShortcutManager
        self.keyboardBindingMapper = keyboardBindingMapper
    }

    func installInitialShortcuts(actions: any KeyboardShortcutActionHandling) throws {
        let registrations = try registrations(for: controller.currentConfig.bindings, actions: actions)
        try shortcutInstaller.replaceShortcuts(registrations)
        installedRegistrations = registrations
    }

    func reload(actions: any KeyboardShortcutActionHandling) throws {
        let loadedConfig = try configStore.load()
        let previousRegistrations = installedRegistrations
        let loadedRegistrations = try registrations(for: loadedConfig.bindings, actions: actions)

        try shortcutInstaller.replaceShortcuts(loadedRegistrations)
        installedRegistrations = loadedRegistrations
        do {
            try controller.applyConfig(loadedConfig, enablePersistence: true)
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
