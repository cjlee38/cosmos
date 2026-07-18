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

    func load() throws -> KkaciConfig {
        throw Error.loadFailed
    }

    func save(_: KkaciConfig) throws {}
}
