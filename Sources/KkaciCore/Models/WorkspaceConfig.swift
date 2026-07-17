import Foundation

public struct SwitcherShortcutConfig: Codable, Equatable {
    public static let empty = SwitcherShortcutConfig()

    public let next: String?
    public let previous: String?

    public init(next: String? = nil, previous: String? = nil) {
        self.next = next
        self.previous = previous
    }
}

public struct ShortcutConfig: Codable, Equatable {
    public static let empty = ShortcutConfig()

    public let workspaceSwitcher: SwitcherShortcutConfig
    public let windowSwitcher: SwitcherShortcutConfig

    public init(
        workspaceSwitcher: SwitcherShortcutConfig = .empty,
        windowSwitcher: SwitcherShortcutConfig = .empty
    ) {
        self.workspaceSwitcher = workspaceSwitcher
        self.windowSwitcher = windowSwitcher
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceSwitcher = "workspace_switcher"
        case windowSwitcher = "window_switcher"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceSwitcher = try container.decodeIfPresent(
            SwitcherShortcutConfig.self,
            forKey: .workspaceSwitcher
        ) ?? .empty
        windowSwitcher = try container.decodeIfPresent(
            SwitcherShortcutConfig.self,
            forKey: .windowSwitcher
        ) ?? .empty
    }
}

public struct WorkspaceShortcutConfig: Codable, Equatable {
    public static let empty = WorkspaceShortcutConfig()

    public let switchWorkspace: String?
    public let moveWindow: String?

    public init(switchWorkspace: String? = nil, moveWindow: String? = nil) {
        self.switchWorkspace = switchWorkspace
        self.moveWindow = moveWindow
    }

    private enum CodingKeys: String, CodingKey {
        case switchWorkspace = "switch"
        case moveWindow = "move_window"
    }
}

public struct WorkspaceConfig: Codable, Equatable {
    public let name: String
    public let display: MonitorSlot
    public let shortcuts: WorkspaceShortcutConfig

    public init(
        name: String,
        display: MonitorSlot = 1,
        shortcuts: WorkspaceShortcutConfig = .empty
    ) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.display = max(display, 1)
        self.shortcuts = shortcuts
    }
}

public struct HotKeyBinding: Equatable {
    public let key: String
    public let command: String
    public let workspace: String?

    public init(key: String, command: String, workspace: String? = nil) {
        self.key = key
        self.command = command
        self.workspace = workspace
    }
}

public struct WorkspaceShortcutBindings {
    private struct Entry {
        let workspace: String
        let key: String
    }

    private static let modifierNames: Set<String> = [
        "ctrl", "control", "option", "alt", "shift", "cmd", "command"
    ]

    private let entries: [Entry]

    public init(_ bindings: [HotKeyBinding]) {
        entries = bindings.compactMap { binding in
            guard binding.command.lowercased() == "workspace",
                  let workspace = binding.workspace?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !workspace.isEmpty,
                  let key = Self.keyName(from: binding.key)
            else {
                return nil
            }
            return Entry(workspace: workspace, key: key)
        }
    }

    public func key(for workspace: String) -> String? {
        entries.first { $0.workspace == workspace }?.key
    }

    public func workspace(for key: String) -> String? {
        let key = key.lowercased()
        return entries.first { $0.key == key }?.workspace
    }

    private static func keyName(from shortcut: String) -> String? {
        let keys = shortcut
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !modifierNames.contains($0) }
        return keys.count == 1 ? keys[0] : nil
    }
}

public struct KkaciConfig: Codable, Equatable {
    public static let currentVersion = 1
    public static let `default` = KkaciConfig(
        workspaces: [
            WorkspaceConfig(
                name: "1",
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: "option+1",
                    moveWindow: "option+shift+1"
                )
            ),
            WorkspaceConfig(
                name: "2",
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: "option+2",
                    moveWindow: "option+shift+2"
                )
            ),
            WorkspaceConfig(
                name: "3",
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: "option+3",
                    moveWindow: "option+shift+3"
                )
            )
        ],
        shortcuts: ShortcutConfig(
            workspaceSwitcher: SwitcherShortcutConfig(
                next: "ctrl+tab",
                previous: "ctrl+shift+tab"
            ),
            windowSwitcher: SwitcherShortcutConfig(
                next: "option+tab",
                previous: "option+shift+tab"
            )
        )
    )

    public let version: Int
    public let shortcuts: ShortcutConfig
    public let workspaces: [WorkspaceConfig]

    public init(
        version: Int = KkaciConfig.currentVersion,
        workspaces: [WorkspaceConfig],
        shortcuts: ShortcutConfig = .empty
    ) {
        self.version = version
        self.shortcuts = shortcuts
        self.workspaces = Self.normalized(workspaces)
    }

    public var bindings: [HotKeyBinding] {
        var result: [HotKeyBinding] = []
        result.append(shortcuts.workspaceSwitcher.next, command: "next-workspace")
        result.append(shortcuts.workspaceSwitcher.previous, command: "previous-workspace")
        result.append(shortcuts.windowSwitcher.next, command: "next-window")
        result.append(shortcuts.windowSwitcher.previous, command: "previous-window")
        for workspace in workspaces {
            result.append(
                workspace.shortcuts.switchWorkspace,
                command: "workspace",
                workspace: workspace.name
            )
            result.append(
                workspace.shortcuts.moveWindow,
                command: "move-window-to-workspace",
                workspace: workspace.name
            )
        }
        return result
    }

    public var workspaceNames: [String] {
        workspaces.map(\.name)
    }

    public func monitorSlot(for workspace: String) -> MonitorSlot {
        workspaces.first { $0.name == workspace }?.display ?? 1
    }

    public func assigningWorkspace(_ workspace: String, toMonitorSlot monitorSlot: MonitorSlot) -> KkaciConfig {
        let workspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard workspaces.contains(where: { $0.name == workspace }), monitorSlot >= 1 else {
            return self
        }

        return KkaciConfig(
            version: version,
            workspaces: workspaces.map { configuredWorkspace in
                guard configuredWorkspace.name == workspace else {
                    return configuredWorkspace
                }
                return WorkspaceConfig(
                    name: configuredWorkspace.name,
                    display: monitorSlot,
                    shortcuts: configuredWorkspace.shortcuts
                )
            },
            shortcuts: shortcuts
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case shortcuts
        case workspaces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported config version: \(version)"
            )
        }

        let shortcuts = try container.decodeIfPresent(ShortcutConfig.self, forKey: .shortcuts) ?? .empty
        let workspaces = try container.decode([WorkspaceConfig].self, forKey: .workspaces)
        guard workspaces.contains(where: { !$0.name.isEmpty }) else {
            throw DecodingError.dataCorruptedError(
                forKey: .workspaces,
                in: container,
                debugDescription: "At least one workspace is required"
            )
        }
        self.init(version: version, workspaces: workspaces, shortcuts: shortcuts)
    }

    private static func normalized(_ workspaces: [WorkspaceConfig]) -> [WorkspaceConfig] {
        workspaces.reduce(into: []) { result, workspace in
            if !workspace.name.isEmpty, !result.contains(where: { $0.name == workspace.name }) {
                result.append(workspace)
            }
        }
    }
}

private extension [HotKeyBinding] {
    mutating func append(_ key: String?, command: String, workspace: String? = nil) {
        guard let key else {
            return
        }
        append(HotKeyBinding(key: key, command: command, workspace: workspace))
    }
}

public protocol KkaciConfigStore {
    func load() throws -> KkaciConfig
    func save(_ config: KkaciConfig) throws
}
