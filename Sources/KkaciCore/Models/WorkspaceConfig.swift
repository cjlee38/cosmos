import Foundation

public struct WorkspaceConfig: Codable, Equatable {
    public let names: [String]
    public let monitorSlotsByName: [String: MonitorSlot]

    public init(names: [String], monitorSlotsByName: [String: MonitorSlot] = [:]) {
        let normalized = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, name in
                if !result.contains(name) {
                    result.append(name)
                }
            }

        let names = normalized.isEmpty ? ["1", "2", "3"] : normalized
        self.names = names
        self.monitorSlotsByName = monitorSlotsByName.reduce(into: [:]) { result, entry in
            let name = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            if names.contains(name), entry.value >= 1 {
                result[name] = entry.value
            }
        }
    }

    public func addingWorkspace(named name: String, monitorSlot: MonitorSlot = 1) -> WorkspaceConfig {
        var monitorSlotsByName = monitorSlotsByName
        monitorSlotsByName[name] = monitorSlot
        return WorkspaceConfig(names: names + [name], monitorSlotsByName: monitorSlotsByName)
    }

    public func monitorSlot(for workspace: String) -> MonitorSlot {
        monitorSlotsByName[workspace] ?? 1
    }

    private enum CodingKeys: String, CodingKey {
        case names
        case monitorSlotsByName = "monitors"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let names = try container.decodeIfPresent([String].self, forKey: .names) ?? ["1", "2", "3"]
        let monitorSlotsByName = try container.decodeIfPresent([String: MonitorSlot].self, forKey: .monitorSlotsByName) ?? [:]
        self.init(names: names, monitorSlotsByName: monitorSlotsByName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(names, forKey: .names)
        if !monitorSlotsByName.isEmpty {
            try container.encode(monitorSlotsByName, forKey: .monitorSlotsByName)
        }
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

    public func addingWorkspace(named name: String, monitorSlot: MonitorSlot = 1) -> KkaciConfig {
        KkaciConfig(
            workspaces: workspaces.addingWorkspace(named: name, monitorSlot: monitorSlot),
            bindings: bindings
        )
    }
}

public protocol KkaciConfigStore {
    func load() throws -> KkaciConfig
    func save(_ config: KkaciConfig) throws
}
