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
