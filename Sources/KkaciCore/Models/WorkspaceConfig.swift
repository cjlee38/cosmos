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
    public let id: WorkspaceID
    public let display: MonitorSlot
    public let shortcuts: WorkspaceShortcutConfig

    public init(
        id: WorkspaceID,
        display: MonitorSlot = 1,
        shortcuts: WorkspaceShortcutConfig = .empty
    ) {
        self.id = id
        self.display = max(display, 1)
        self.shortcuts = shortcuts
    }

    public static func defaultShortcuts(for id: WorkspaceID) -> WorkspaceShortcutConfig {
        WorkspaceShortcutConfig(
            switchWorkspace: "option+\(id.defaultShortcutKey)",
            moveWindow: "option+shift+\(id.defaultShortcutKey)"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case display
        case shortcuts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(WorkspaceID.self, forKey: .id),
            display: container.decode(MonitorSlot.self, forKey: .display),
            shortcuts: container.decode(WorkspaceShortcutConfig.self, forKey: .shortcuts)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(display, forKey: .display)
        try container.encode(shortcuts, forKey: .shortcuts)
    }
}

public struct KkaciConfig: Codable, Equatable {
    public static let currentVersion = 1
    public static let `default` = KkaciConfig(
        workspaces: [
            WorkspaceConfig(
                id: "1",
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: "option+1",
                    moveWindow: "option+shift+1"
                )
            ),
            WorkspaceConfig(
                id: "2",
                shortcuts: WorkspaceShortcutConfig(
                    switchWorkspace: "option+2",
                    moveWindow: "option+shift+2"
                )
            ),
            WorkspaceConfig(
                id: "3",
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

    public var configuredShortcuts: [ConfiguredShortcut] {
        var result: [ConfiguredShortcut] = []
        result.append(shortcuts.workspaceSwitcher.next, target: .workspaceSwitcherNext)
        result.append(shortcuts.workspaceSwitcher.previous, target: .workspaceSwitcherPrevious)
        result.append(shortcuts.windowSwitcher.next, target: .windowSwitcherNext)
        result.append(shortcuts.windowSwitcher.previous, target: .windowSwitcherPrevious)
        for workspace in workspaces {
            result.append(
                workspace.shortcuts.switchWorkspace,
                target: .switchWorkspace(workspace.id)
            )
            result.append(
                workspace.shortcuts.moveWindow,
                target: .moveWindow(workspace.id)
            )
        }
        return result
    }

    public func assigningWorkspace(_ workspaceID: WorkspaceID, toMonitorSlot monitorSlot: MonitorSlot) -> KkaciConfig {
        guard workspaces.contains(where: { $0.id == workspaceID }),
              monitorSlot >= 1
        else {
            return self
        }

        return KkaciConfig(
            version: version,
            workspaces: workspaces.map { configuredWorkspace in
                guard configuredWorkspace.id == workspaceID else {
                    return configuredWorkspace
                }
                return WorkspaceConfig(
                    id: configuredWorkspace.id,
                    display: monitorSlot,
                    shortcuts: configuredWorkspace.shortcuts
                )
            },
            shortcuts: shortcuts
        )
    }

    public func addingWorkspace(_ id: WorkspaceID, display: MonitorSlot = 1) -> KkaciConfig? {
        addingWorkspaces([id], display: display)
    }

    public func addingWorkspaces(_ ids: [WorkspaceID], display: MonitorSlot = 1) -> KkaciConfig? {
        let configuredIDs = Set(workspaces.map(\.id))
        let newIDs = Set(ids).subtracting(configuredIDs).sorted()
        guard !newIDs.isEmpty else {
            return nil
        }
        return KkaciConfig(
            version: version,
            workspaces: workspaces + newIDs.map { id in
                WorkspaceConfig(
                    id: id,
                    display: display,
                    shortcuts: WorkspaceConfig.defaultShortcuts(for: id)
                )
            },
            shortcuts: shortcuts
        )
    }

    public func removingWorkspace(_ id: WorkspaceID) -> KkaciConfig? {
        guard workspaces.count > 1, workspaces.contains(where: { $0.id == id }) else {
            return nil
        }
        return KkaciConfig(
            version: version,
            workspaces: workspaces.filter { $0.id != id },
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
        guard !workspaces.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .workspaces,
                in: container,
                debugDescription: "At least one workspace is required"
            )
        }
        guard Set(workspaces.map(\.id)).count == workspaces.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .workspaces,
                in: container,
                debugDescription: "Workspace IDs must be unique"
            )
        }
        self.init(version: version, workspaces: workspaces, shortcuts: shortcuts)
    }

    private static func normalized(_ workspaces: [WorkspaceConfig]) -> [WorkspaceConfig] {
        precondition(!workspaces.isEmpty, "At least one workspace is required")
        precondition(Set(workspaces.map(\.id)).count == workspaces.count, "Workspace IDs must be unique")
        return workspaces.sorted { $0.id < $1.id }
    }
}

private extension [ConfiguredShortcut] {
    mutating func append(_ key: String?, target: ShortcutTarget) {
        guard let key else {
            return
        }
        append(ConfiguredShortcut(key: key, target: target))
    }
}

public protocol KkaciConfigStore {
    func load() throws -> KkaciConfig
    func save(_ config: KkaciConfig) throws
}
