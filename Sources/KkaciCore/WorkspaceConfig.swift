import Foundation
import TOMLKit

public struct WorkspaceConfig: Codable, Equatable {
    public let names: [String]

    public init(names: [String]) {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) {
                    result.append(name)
                }
            }

        self.names = normalized.isEmpty ? ["1", "2", "3"] : normalized
    }

    public func addingWorkspace(named name: String) -> WorkspaceConfig {
        WorkspaceConfig(names: names + [name])
    }
}

public struct HotKeyBinding: Codable, Equatable {
    public let key: String
    public let command: String
    public let workspace: String?

    public init(key: String, command: String, workspace: String? = nil) {
        self.key = key
        self.command = command
        self.workspace = workspace
    }
}

public struct KkaciConfig: Codable, Equatable {
    public static let `default` = KkaciConfig(
        workspaces: WorkspaceConfig(names: ["1", "2", "3"]),
        bindings: [
            HotKeyBinding(key: "ctrl+tab", command: "next-workspace"),
            HotKeyBinding(key: "ctrl+shift+tab", command: "previous-workspace"),
            HotKeyBinding(key: "option+tab", command: "next-window"),
            HotKeyBinding(key: "option+shift+tab", command: "previous-window"),
            HotKeyBinding(key: "option+1", command: "workspace", workspace: "1"),
            HotKeyBinding(key: "option+2", command: "workspace", workspace: "2"),
            HotKeyBinding(key: "option+3", command: "workspace", workspace: "3"),
            HotKeyBinding(key: "option+shift+1", command: "move-window-to-workspace", workspace: "1"),
            HotKeyBinding(key: "option+shift+2", command: "move-window-to-workspace", workspace: "2"),
            HotKeyBinding(key: "option+shift+3", command: "move-window-to-workspace", workspace: "3"),
        ]
    )

    public let workspaces: WorkspaceConfig
    public let bindings: [HotKeyBinding]

    public init(workspaces: WorkspaceConfig, bindings: [HotKeyBinding]) {
        self.workspaces = workspaces
        self.bindings = bindings
    }

    public func addingWorkspace(named name: String) -> KkaciConfig {
        KkaciConfig(
            workspaces: workspaces.addingWorkspace(named: name),
            bindings: bindings
        )
    }
}

public protocol KkaciConfigStore {
    func load() throws -> KkaciConfig
    func save(_ config: KkaciConfig) throws
}

public final class FileKkaciConfigStore: KkaciConfigStore {
    public static let `default` = FileKkaciConfigStore(
        url: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kkaci", isDirectory: true)
            .appendingPathComponent("config.toml")
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

        let toml = try String(contentsOf: url, encoding: .utf8)
        let table = try TOMLTable(string: toml)
        return try TOMLDecoder().decode(KkaciConfig.self, from: table)
    }

    public func save(_ config: KkaciConfig) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let table: TOMLTable = try TOMLEncoder().encode(config)
        let toml = table.convert(to: .toml)
        try toml.write(to: url, atomically: true, encoding: .utf8)
    }
}
