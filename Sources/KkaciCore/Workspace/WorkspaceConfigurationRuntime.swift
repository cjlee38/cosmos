import Foundation

final class WorkspaceConfigurationRuntime {
    private let configStore: (any KkaciConfigStore)?
    private var config: KkaciConfig
    private var isPersistenceEnabled: Bool
    let startupLoadError: Error?

    init(
        configStore: (any KkaciConfigStore)?,
        isPersistenceEnabled: Bool
    ) {
        self.configStore = configStore
        let startupConfig = Self.loadStartupConfig(from: configStore)
        config = startupConfig.config
        startupLoadError = startupConfig.loadError
        self.isPersistenceEnabled = configStore != nil && isPersistenceEnabled && startupConfig.loadError == nil
    }

    var currentConfig: KkaciConfig {
        config
    }

    func ensureWorkspace(
        _ workspace: String,
        state: inout WorkspaceState,
        monitorSlot: MonitorSlot? = nil
    ) throws -> String {
        let workspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty else {
            throw WorkspaceError.invalidWorkspaceName(workspace)
        }

        if state.containsWorkspace(workspace) {
            return workspace
        }

        let monitorSlot = monitorSlot ?? state.monitorSlot(for: state.activeWorkspace)
        let nextConfig = config.addingWorkspace(named: workspace, monitorSlot: monitorSlot)
        if isPersistenceEnabled {
            try configStore?.save(nextConfig)
        }

        config = nextConfig
        state.addWorkspace(workspace, monitorSlot: monitorSlot)
        return workspace
    }

    func apply(
        _ config: KkaciConfig,
        enablePersistence: Bool,
        state: inout WorkspaceState
    ) {
        isPersistenceEnabled = configStore != nil && enablePersistence
        state.applyWorkspaces(config.workspaces)
        self.config = KkaciConfig(
            workspaces: state.workspaceConfig,
            bindings: config.bindings
        )
    }

    private static func loadStartupConfig(from configStore: (any KkaciConfigStore)?) -> StartupConfigLoad {
        guard let configStore else {
            return StartupConfigLoad(config: .default, loadError: nil)
        }

        do {
            return try StartupConfigLoad(config: configStore.load(), loadError: nil)
        } catch {
            return StartupConfigLoad(config: .default, loadError: error)
        }
    }
}

private struct StartupConfigLoad {
    let config: KkaciConfig
    let loadError: Error?
}
