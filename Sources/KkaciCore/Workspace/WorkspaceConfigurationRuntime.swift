import Foundation

final class WorkspaceConfigurationRuntime {
    private let configStore: (any KkaciConfigStore)?
    private var bindings: [HotKeyBinding]
    private var isPersistenceEnabled: Bool
    let startupLoadError: Error?

    init(
        configStore: (any KkaciConfigStore)?,
        bindings: [HotKeyBinding],
        isPersistenceEnabled: Bool,
        startupLoadError: Error?
    ) {
        self.configStore = configStore
        self.bindings = bindings
        self.isPersistenceEnabled = configStore != nil && isPersistenceEnabled
        self.startupLoadError = startupLoadError
    }

    func currentConfig(workspaces: WorkspaceConfig) -> KkaciConfig {
        KkaciConfig(workspaces: workspaces, bindings: bindings)
    }

    private func apply(
        _ config: KkaciConfig,
        enablePersistence: Bool?,
        state: inout WorkspaceState
    ) {
        if let enablePersistence {
            isPersistenceEnabled = configStore != nil && enablePersistence
        }
        state.applyWorkspaces(config.workspaces)
        bindings = config.bindings
    }

    func applyTransaction(
        _ config: KkaciConfig,
        enablePersistence: Bool?,
        saveConfig: Bool,
        state: inout WorkspaceState,
        applyVisibility: (inout WorkspaceState) throws -> Void
    ) throws {
        let previousState = state
        let previousConfiguration = snapshot

        apply(config, enablePersistence: enablePersistence, state: &state)
        do {
            try applyVisibility(&state)
            if saveConfig {
                try saveIfEnabled(currentConfig(workspaces: state.workspaceConfig))
            }
        } catch let applyError {
            restore(previousConfiguration)
            state.restoreWorkspaceConfiguration(from: previousState)
            do {
                try applyVisibility(&state)
            } catch let rollbackError {
                throw WorkspaceTransactionError(
                    applyError: applyError,
                    rollbackError: rollbackError
                )
            }
            state = previousState
            throw applyError
        }
    }

    private func saveIfEnabled(_ config: KkaciConfig) throws {
        if isPersistenceEnabled {
            try configStore?.save(config)
        }
    }

    private var snapshot: WorkspaceConfigurationSnapshot {
        WorkspaceConfigurationSnapshot(
            bindings: bindings,
            isPersistenceEnabled: isPersistenceEnabled
        )
    }

    private func restore(_ snapshot: WorkspaceConfigurationSnapshot) {
        bindings = snapshot.bindings
        isPersistenceEnabled = snapshot.isPersistenceEnabled
    }

    static func bootstrap(
        from configStore: (any KkaciConfigStore)?,
        isPersistenceEnabled: Bool
    ) -> WorkspaceConfigurationBootstrap {
        let startup: (config: KkaciConfig, loadError: Error?)
        if let configStore {
            do {
                startup = try (configStore.load(), nil)
            } catch {
                startup = (.default, error)
            }
        } else {
            startup = (.default, nil)
        }

        let runtime = WorkspaceConfigurationRuntime(
            configStore: configStore,
            bindings: startup.config.bindings,
            isPersistenceEnabled: isPersistenceEnabled && startup.loadError == nil,
            startupLoadError: startup.loadError
        )
        return WorkspaceConfigurationBootstrap(config: startup.config, runtime: runtime)
    }
}

struct WorkspaceConfigurationBootstrap {
    let config: KkaciConfig
    let runtime: WorkspaceConfigurationRuntime
}

private struct WorkspaceConfigurationSnapshot {
    let bindings: [HotKeyBinding]
    let isPersistenceEnabled: Bool
}
