import Foundation

public enum ShortcutTarget: Hashable {
    case workspaceSwitcherNext
    case workspaceSwitcherPrevious
    case windowSwitcherNext
    case windowSwitcherPrevious
    case switchWorkspace(WorkspaceID)
    case moveWindow(WorkspaceID)
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

public extension KkaciConfig {
    func updatingShortcut(_ shortcut: String?, for target: ShortcutTarget) -> KkaciConfig? {
        let shortcut = normalizedShortcut(shortcut)
        switch target {
        case .workspaceSwitcherNext:
            return replacingShortcuts(ShortcutConfig(
                workspaceSwitcher: SwitcherShortcutConfig(
                    next: shortcut,
                    previous: shortcuts.workspaceSwitcher.previous
                ),
                windowSwitcher: shortcuts.windowSwitcher
            ))
        case .workspaceSwitcherPrevious:
            return replacingShortcuts(ShortcutConfig(
                workspaceSwitcher: SwitcherShortcutConfig(
                    next: shortcuts.workspaceSwitcher.next,
                    previous: shortcut
                ),
                windowSwitcher: shortcuts.windowSwitcher
            ))
        case .windowSwitcherNext:
            return replacingShortcuts(ShortcutConfig(
                workspaceSwitcher: shortcuts.workspaceSwitcher,
                windowSwitcher: SwitcherShortcutConfig(
                    next: shortcut,
                    previous: shortcuts.windowSwitcher.previous
                )
            ))
        case .windowSwitcherPrevious:
            return replacingShortcuts(ShortcutConfig(
                workspaceSwitcher: shortcuts.workspaceSwitcher,
                windowSwitcher: SwitcherShortcutConfig(
                    next: shortcuts.windowSwitcher.next,
                    previous: shortcut
                )
            ))
        case let .switchWorkspace(id):
            return updatingWorkspaceShortcut(id, shortcut: shortcut, moveWindow: false)
        case let .moveWindow(id):
            return updatingWorkspaceShortcut(id, shortcut: shortcut, moveWindow: true)
        }
    }
}

private extension KkaciConfig {
    func replacingShortcuts(_ shortcuts: ShortcutConfig) -> KkaciConfig {
        KkaciConfig(version: version, workspaces: workspaces, shortcuts: shortcuts)
    }

    func updatingWorkspaceShortcut(
        _ id: WorkspaceID,
        shortcut: String?,
        moveWindow: Bool
    ) -> KkaciConfig? {
        guard workspaces.contains(where: { $0.id == id }) else {
            return nil
        }
        return KkaciConfig(
            version: version,
            workspaces: workspaces.map { workspace in
                guard workspace.id == id else {
                    return workspace
                }
                let shortcuts = WorkspaceShortcutConfig(
                    switchWorkspace: moveWindow ? workspace.shortcuts.switchWorkspace : shortcut,
                    moveWindow: moveWindow ? shortcut : workspace.shortcuts.moveWindow
                )
                return WorkspaceConfig(
                    id: workspace.id,
                    display: workspace.display,
                    shortcuts: shortcuts
                )
            },
            shortcuts: shortcuts
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
