@testable import CosmosCore

final class InMemorySpaceConfigStore: CosmosConfigStore {
    private(set) var savedConfigs: [CosmosConfig] = []

    func load() throws -> CosmosConfig {
        savedConfigs.last ?? .default
    }

    func save(_ config: CosmosConfig) throws {
        savedConfigs.append(config)
    }
}

final class FailingLoadSpaceConfigStore: CosmosConfigStore {
    enum Error: Swift.Error, Equatable {
        case loadFailed
    }

    func load() throws -> CosmosConfig {
        throw Error.loadFailed
    }

    func save(_: CosmosConfig) throws {}
}
