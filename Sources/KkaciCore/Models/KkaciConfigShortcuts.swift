import Foundation

public enum ShortcutTarget: Hashable {
    case workspaceSwitcherNext
    case workspaceSwitcherPrevious
    case windowSwitcherNext
    case windowSwitcherPrevious
    case switchWorkspace(WorkspaceID)
    case moveWindow(WorkspaceID)
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
                    name: workspace.name,
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
