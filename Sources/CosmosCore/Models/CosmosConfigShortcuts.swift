import Foundation

public enum ShortcutTarget: Hashable {
    case spaceSwitcher
    case windowSwitcher
    case centerWindow
    case switchSpace(SpaceID)
    case moveWindow(SpaceID)
}

public enum ShortcutModifier: String, CaseIterable, Hashable {
    case control
    case option
    case shift
    case command
}

public struct Shortcut: Equatable {
    public let modifiers: [ShortcutModifier]
    public let key: String

    public init(parsing value: String) throws {
        let parts = value
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw ShortcutParsingError.empty
        }

        var modifiers = Set<ShortcutModifier>()
        var key: String?
        for part in parts {
            if let modifier = ShortcutModifier(configName: part) {
                modifiers.insert(modifier)
            } else if key == nil {
                key = part
            } else {
                throw ShortcutParsingError.multipleKeys(value)
            }
        }

        guard let key else {
            throw ShortcutParsingError.missingKey(value)
        }

        self.modifiers = ShortcutModifier.allCases.filter(modifiers.contains)
        self.key = key
    }
}

enum ShortcutParsingError: Error, CustomStringConvertible {
    case empty
    case missingKey(String)
    case multipleKeys(String)

    var description: String {
        switch self {
        case .empty:
            "empty key"
        case let .missingKey(value):
            "missing key in \(value)"
        case let .multipleKeys(value):
            "multiple keys in \(value)"
        }
    }
}

private extension ShortcutModifier {
    init?(configName: String) {
        switch configName {
        case "ctrl", "control":
            self = .control
        case "option", "alt":
            self = .option
        case "shift":
            self = .shift
        case "cmd", "command":
            self = .command
        default:
            return nil
        }
    }
}

public struct ConfiguredShortcut: Equatable {
    public let key: String
    public let target: ShortcutTarget

    public init(key: String, target: ShortcutTarget) {
        self.key = key
        self.target = target
    }

    public func parsed() throws -> Shortcut {
        try Shortcut(parsing: key)
    }
}

public extension CosmosConfig {
    func updatingShortcut(_ shortcut: String?, for target: ShortcutTarget) -> CosmosConfig? {
        let shortcut = normalizedShortcut(shortcut)
        switch target {
        case .spaceSwitcher:
            return replacingSwitcherShortcuts(SwitcherShortcutConfig(
                space: shortcut,
                window: switcher.shortcuts.window
            ))
        case .windowSwitcher:
            return replacingSwitcherShortcuts(SwitcherShortcutConfig(
                space: switcher.shortcuts.space,
                window: shortcut
            ))
        case .centerWindow:
            return replacingWindowShortcuts(WindowShortcutConfig(center: shortcut))
        case let .switchSpace(id):
            return updatingSpaceShortcut(id, shortcut: shortcut, moveWindow: false)
        case let .moveWindow(id):
            return updatingSpaceShortcut(id, shortcut: shortcut, moveWindow: true)
        }
    }
}

private extension CosmosConfig {
    func replacingSwitcherShortcuts(_ shortcuts: SwitcherShortcutConfig) -> CosmosConfig {
        CosmosConfig(
            version: version,
            spaces: spaces,
            switcher: SwitcherConfig(shortcuts: shortcuts),
            window: window
        )
    }

    func replacingWindowShortcuts(_ shortcuts: WindowShortcutConfig) -> CosmosConfig {
        CosmosConfig(
            version: version,
            spaces: spaces,
            switcher: switcher,
            window: WindowConfig(shortcuts: shortcuts)
        )
    }

    func updatingSpaceShortcut(
        _ id: SpaceID,
        shortcut: String?,
        moveWindow: Bool
    ) -> CosmosConfig? {
        guard spaces.contains(where: { $0.id == id }) else {
            return nil
        }
        return CosmosConfig(
            version: version,
            spaces: spaces.map { space in
                guard space.id == id else {
                    return space
                }
                let shortcuts = SpaceShortcutConfig(
                    switchSpace: moveWindow ? space.shortcuts.switchSpace : shortcut,
                    moveWindow: moveWindow ? shortcut : space.shortcuts.moveWindow
                )
                return SpaceConfig(
                    id: space.id,
                    display: space.display,
                    shortcuts: shortcuts
                )
            },
            switcher: switcher,
            window: window
        )
    }

    func normalizedShortcut(_ shortcut: String?) -> String? {
        guard let shortcut = shortcut?.trimmingCharacters(in: .whitespacesAndNewlines),
              !shortcut.isEmpty
        else {
            return nil
        }
        return shortcut
    }
}
