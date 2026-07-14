@testable import KkaciCore

final class InMemoryWorkspaceConfigStore: KkaciConfigStore {
    private(set) var savedConfigs: [KkaciConfig] = []

    func load() throws -> KkaciConfig {
        savedConfigs.last ?? .default
    }

    func save(_ config: KkaciConfig) throws {
        savedConfigs.append(config)
    }
}

final class FailingLoadWorkspaceConfigStore: KkaciConfigStore {
    enum Error: Swift.Error, Equatable {
        case loadFailed
    }

    private(set) var savedConfigs: [KkaciConfig] = []

    func load() throws -> KkaciConfig {
        throw Error.loadFailed
    }

    func save(_ config: KkaciConfig) throws {
        savedConfigs.append(config)
    }
}

final class FailingSaveWorkspaceConfigStore: KkaciConfigStore {
    enum Error: Swift.Error, Equatable {
        case saveFailed
    }

    let loadedConfig: KkaciConfig
    private(set) var saveAttempts: [KkaciConfig] = []

    init(loadedConfig: KkaciConfig = .default) {
        self.loadedConfig = loadedConfig
    }

    func load() throws -> KkaciConfig {
        loadedConfig
    }

    func save(_ config: KkaciConfig) throws {
        saveAttempts.append(config)
        throw Error.saveFailed
    }
}
