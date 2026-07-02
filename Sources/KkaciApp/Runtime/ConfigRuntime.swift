import Foundation
import KkaciCore

final class ConfigRuntime {
    let configURL: URL?
    private let configStore: any KkaciConfigStore
    private let controller: WorkspaceController
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let keyboardBindingMapper: KeyboardBindingMapper

    init(
        configStore: any KkaciConfigStore,
        configURL: URL?,
        controller: WorkspaceController,
        keyboardShortcutManager: KeyboardShortcutManager,
        keyboardBindingMapper: KeyboardBindingMapper
    ) {
        self.configStore = configStore
        self.configURL = configURL
        self.controller = controller
        self.keyboardShortcutManager = keyboardShortcutManager
        self.keyboardBindingMapper = keyboardBindingMapper
    }

    func installInitialShortcuts(actions: any KeyboardShortcutActionHandling) throws {
        try installShortcuts(for: controller.currentConfig.bindings, actions: actions)
    }

    func reload(actions: any KeyboardShortcutActionHandling) throws {
        let loadedConfig = try configStore.load()
        try installShortcuts(for: loadedConfig.bindings, actions: actions)
        try controller.applyConfig(loadedConfig, enablePersistence: true)
    }

    private func installShortcuts(
        for bindings: [HotKeyBinding],
        actions: any KeyboardShortcutActionHandling
    ) throws {
        try keyboardShortcutManager.replaceShortcuts(
            keyboardBindingMapper.registrations(
                for: bindings,
                actions: actions
            )
        )
    }
}
