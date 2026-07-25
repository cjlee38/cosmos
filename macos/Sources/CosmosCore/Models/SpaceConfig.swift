import Foundation

public struct SwitcherShortcutConfig: Codable, Equatable {
    public static let empty = SwitcherShortcutConfig()

    public let space: String?
    public let window: String?

    public init(
        space: String? = nil,
        window: String? = nil
    ) {
        self.space = space
        self.window = window
    }
}

public struct SwitcherConfig: Codable, Equatable {
    public static let empty = SwitcherConfig()

    public let shortcuts: SwitcherShortcutConfig

    public init(shortcuts: SwitcherShortcutConfig = .empty) {
        self.shortcuts = shortcuts
    }
}

public struct WindowShortcutConfig: Codable, Equatable {
    public static let `default` = WindowShortcutConfig(center: "option+command+c")

    public let center: String?

    public init(center: String? = nil) {
        self.center = center
    }
}

public struct WindowConfig: Codable, Equatable {
    public static let `default` = WindowConfig(shortcuts: .default)

    public let shortcuts: WindowShortcutConfig

    public init(shortcuts: WindowShortcutConfig = .default) {
        self.shortcuts = shortcuts
    }
}

public struct SpaceShortcutConfig: Codable, Equatable {
    public static let empty = SpaceShortcutConfig()

    public let switchSpace: String?
    public let moveWindow: String?

    public init(switchSpace: String? = nil, moveWindow: String? = nil) {
        self.switchSpace = switchSpace
        self.moveWindow = moveWindow
    }

    private enum CodingKeys: String, CodingKey {
        case switchSpace = "switch"
        case moveWindow = "move_window"
    }
}

public struct SpaceConfig: Codable, Equatable {
    public let id: SpaceID
    public let display: MonitorSlot
    public let shortcuts: SpaceShortcutConfig

    public init(
        id: SpaceID,
        display: MonitorSlot = 1,
        shortcuts: SpaceShortcutConfig = .empty
    ) {
        self.id = id
        self.display = max(display, 1)
        self.shortcuts = shortcuts
    }

    public static func defaultShortcuts(for id: SpaceID) -> SpaceShortcutConfig {
        SpaceShortcutConfig(
            switchSpace: "option+\(id.defaultShortcutKey)",
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
            id: container.decode(SpaceID.self, forKey: .id),
            display: container.decode(MonitorSlot.self, forKey: .display),
            shortcuts: container.decode(SpaceShortcutConfig.self, forKey: .shortcuts)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(display, forKey: .display)
        try container.encode(shortcuts, forKey: .shortcuts)
    }
}

public struct CosmosConfig: Codable, Equatable {
    public static let currentVersion = 1
    public static let `default` = CosmosConfig(
        spaces: [
            SpaceConfig(
                id: "1",
                shortcuts: SpaceShortcutConfig(
                    switchSpace: "option+1",
                    moveWindow: "option+shift+1"
                )
            ),
            SpaceConfig(
                id: "2",
                shortcuts: SpaceShortcutConfig(
                    switchSpace: "option+2",
                    moveWindow: "option+shift+2"
                )
            ),
            SpaceConfig(
                id: "3",
                shortcuts: SpaceShortcutConfig(
                    switchSpace: "option+3",
                    moveWindow: "option+shift+3"
                )
            )
        ],
        switcher: SwitcherConfig(
            shortcuts: SwitcherShortcutConfig(
                space: "option+shift+tab",
                window: "option+tab"
            )
        ),
        window: .default
    )

    public let version: Int
    public let switcher: SwitcherConfig
    public let window: WindowConfig
    public let spaces: [SpaceConfig]

    public init(
        version: Int = CosmosConfig.currentVersion,
        spaces: [SpaceConfig],
        switcher: SwitcherConfig = .empty,
        window: WindowConfig = .default
    ) {
        self.version = version
        self.switcher = switcher
        self.window = window
        self.spaces = Self.normalized(spaces)
    }

    public var configuredShortcuts: [ConfiguredShortcut] {
        var result: [ConfiguredShortcut] = []
        result.append(switcher.shortcuts.space, target: .spaceSwitcher)
        result.append(switcher.shortcuts.window, target: .windowSwitcher)
        result.append(window.shortcuts.center, target: .centerWindow)
        for space in spaces {
            result.append(
                space.shortcuts.switchSpace,
                target: .switchSpace(space.id)
            )
            result.append(
                space.shortcuts.moveWindow,
                target: .moveWindow(space.id)
            )
        }
        return result
    }

    public func assigningSpace(_ spaceID: SpaceID, toMonitorSlot monitorSlot: MonitorSlot) -> CosmosConfig {
        guard spaces.contains(where: { $0.id == spaceID }),
              monitorSlot >= 1
        else {
            return self
        }

        return CosmosConfig(
            version: version,
            spaces: spaces.map { configuredSpace in
                guard configuredSpace.id == spaceID else {
                    return configuredSpace
                }
                return SpaceConfig(
                    id: configuredSpace.id,
                    display: monitorSlot,
                    shortcuts: configuredSpace.shortcuts
                )
            },
            switcher: switcher,
            window: window
        )
    }

    public func addingSpace(_ id: SpaceID, display: MonitorSlot = 1) -> CosmosConfig? {
        addingSpaces([id], display: display)
    }

    public func addingSpaces(_ ids: [SpaceID], display: MonitorSlot = 1) -> CosmosConfig? {
        let configuredIDs = Set(spaces.map(\.id))
        let newIDs = Set(ids).subtracting(configuredIDs).sorted()
        guard !newIDs.isEmpty else {
            return nil
        }
        return CosmosConfig(
            version: version,
            spaces: spaces + newIDs.map { id in
                SpaceConfig(
                    id: id,
                    display: display,
                    shortcuts: SpaceConfig.defaultShortcuts(for: id)
                )
            },
            switcher: switcher,
            window: window
        )
    }

    public func removingSpace(_ id: SpaceID) -> CosmosConfig? {
        guard spaces.count > 1, spaces.contains(where: { $0.id == id }) else {
            return nil
        }
        return CosmosConfig(
            version: version,
            spaces: spaces.filter { $0.id != id },
            switcher: switcher,
            window: window
        )
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case switcher
        case window
        case spaces
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

        let switcher = try container.decodeIfPresent(SwitcherConfig.self, forKey: .switcher) ?? .empty
        let window = try container.decodeIfPresent(WindowConfig.self, forKey: .window) ?? .default
        let spaces = try container.decode([SpaceConfig].self, forKey: .spaces)
        guard !spaces.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .spaces,
                in: container,
                debugDescription: "At least one space is required"
            )
        }
        guard Set(spaces.map(\.id)).count == spaces.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .spaces,
                in: container,
                debugDescription: "Space IDs must be unique"
            )
        }
        self.init(version: version, spaces: spaces, switcher: switcher, window: window)
    }

    private static func normalized(_ spaces: [SpaceConfig]) -> [SpaceConfig] {
        precondition(!spaces.isEmpty, "At least one space is required")
        precondition(Set(spaces.map(\.id)).count == spaces.count, "Space IDs must be unique")
        return spaces.sorted { $0.id < $1.id }
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

public protocol CosmosConfigStore {
    func load() throws -> CosmosConfig
    func save(_ config: CosmosConfig) throws
}
