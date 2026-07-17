import Foundation
import Yams

public final class FileKkaciConfigStore: KkaciConfigStore {
    private static let fileHeader = """
    # Kkaci configuration file
    #
    # - Warning
    #   - This file may be rewritten by Kkaci Settings.
    #   - Custom comments and formatting may be removed. The last save wins.
    #   - Invalid changes are not applied; Kkaci keeps the previous valid configuration.
    #
    # - Shortcut modifiers
    #   - Control: 'control'
    #   - Option: 'option'
    #   - Shift: 'shift'
    #   - Command: 'command'
    #   - Combine modifiers and a key with '+'. Example: 'option+shift+1'
    #
    # - Workspace IDs
    #   - Valid IDs are the numbers 0 through 9 and the letters A through Z.
    #   - Letter IDs are case-insensitive and are saved as uppercase.
    #   - Workspace IDs must be unique.
    #   - 'name' is an optional display alias. Workspace identity and shortcuts still use 'id'.
    #
    # - Display slots
    #   - A display slot is an integer assigned to each display by Kkaci.
    #   - Check assigned slots in Settings > Workspaces or run 'kkaci displays'.
    #   - The main display is slot 1. Other displays are assigned slots 2, 3, and so on.
    #   - Mirrored displays are ignored and do not receive slots.
    """

    public static let `default` = FileKkaciConfigStore(
        url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("kkaci", isDirectory: true)
            .appendingPathComponent("config.yaml")
    )

    public let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func load() throws -> KkaciConfig {
        guard fileManager.fileExists(atPath: url.path) else {
            let config = KkaciConfig.default
            try save(config)
            return config
        }

        let yaml = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(KkaciConfig.self, from: yaml)
    }

    public func save(_ config: KkaciConfig) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let yaml = try YAMLEncoder().encode(config)
        let content = "\(Self.fileHeader)\n\(yaml)"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
