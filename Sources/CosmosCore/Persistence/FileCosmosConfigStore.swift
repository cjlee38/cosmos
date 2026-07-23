import Foundation
import Yams

public final class FileCosmosConfigStore: CosmosConfigStore {
    private static let fileHeader = """
    # Cosmos configuration file
    #
    # - Warning
    #   - This file may be rewritten by Cosmos Settings.
    #   - Custom comments and formatting may be removed. The last save wins.
    #   - Invalid changes are not applied; Cosmos keeps the previous valid configuration.
    #
    # - Shortcut modifiers
    #   - Control: 'control'
    #   - Option: 'option'
    #   - Shift: 'shift'
    #   - Command: 'command'
    #   - Combine modifiers and a key with '+'. Example: 'option+shift+1'
    #
    # - Space IDs
    #   - Valid IDs are the numbers 0 through 9 and the letters A through Z.
    #   - Letter IDs are case-insensitive and are saved as uppercase.
    #   - Space IDs must be unique.
    #
    # - Display slots
    #   - A display slot is an integer assigned to each display by Cosmos.
    #   - Check assigned slots in Settings > Spaces or run 'cosmos displays'.
    #   - The main display is slot 1. Other displays are assigned slots 2, 3, and so on.
    #   - Mirrored displays are ignored and do not receive slots.
    """

    public static let `default` = FileCosmosConfigStore(
        url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("cosmos", isDirectory: true)
            .appendingPathComponent("config.yaml")
    )

    public let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func load() throws -> CosmosConfig {
        guard fileManager.fileExists(atPath: url.path) else {
            let config = CosmosConfig.default
            try save(config)
            return config
        }

        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(CosmosConfig.self, from: yaml)
    }

    public func save(_ config: CosmosConfig) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let yaml = try YAMLEncoder().encode(config)
        let content = "\(Self.fileHeader)\n\(yaml)"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
