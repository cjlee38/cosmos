import KkaciCore

protocol KeyboardShortcutActionHandling: AnyObject {
    func stepWorkspaceSwitcher(direction: SwitcherDirection)
    func commitWorkspaceSwitcher()
    func stepWindowSwitcher(direction: SwitcherDirection, wraps: Bool)
    func commitWindowSwitcher()
    func cancelSwitcher()
    func switchWorkspace(to workspace: WorkspaceID)
    func moveFocusedWindow(to workspace: WorkspaceID)
}

final class KeyboardBindingMapper {
    func registrations(
        for shortcuts: [ConfiguredShortcut],
        actions: any KeyboardShortcutActionHandling
    ) -> [KeyboardShortcutRegistration] {
        shortcuts.map { shortcut in
            registration(for: shortcut, actions: actions)
        }
    }

    private func registration(
        for shortcut: ConfiguredShortcut,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        switch shortcut.target {
        case .workspaceSwitcher:
            workspaceSwitcherRegistration(
                shortcut,
                name: "Cycle Workspace",
                actions: actions
            )
        case .windowSwitcher:
            windowSwitcherRegistration(
                shortcut,
                name: "Cycle Window",
                actions: actions
            )
        case let .switchWorkspace(workspace):
            switchWorkspaceRegistration(shortcut, workspace: workspace, actions: actions)
        case let .moveWindow(workspace):
            moveFocusedWindowRegistration(shortcut, workspace: workspace, actions: actions)
        }
    }

    private func workspaceSwitcherRegistration(
        _ shortcut: ConfiguredShortcut,
        name: String,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .hold(
            key: shortcut.key,
            name: name,
            target: shortcut.target,
            releaseGroup: "workspace-switcher",
            actions: .init(
                onPress: { [weak actions] in
                    actions?.stepWorkspaceSwitcher(direction: .forward)
                },
                onRelease: { [weak actions] in
                    actions?.commitWorkspaceSwitcher()
                },
                onCancel: { [weak actions] in
                    actions?.cancelSwitcher()
                }
            )
        )
    }

    private func windowSwitcherRegistration(
        _ shortcut: ConfiguredShortcut,
        name: String,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .hold(
            key: shortcut.key,
            name: name,
            target: shortcut.target,
            releaseGroup: "window-switcher",
            actions: .init(
                onPress: { [weak actions] in
                    actions?.stepWindowSwitcher(direction: .forward, wraps: true)
                },
                onRepeat: { [weak actions] in
                    actions?.stepWindowSwitcher(direction: .forward, wraps: false)
                },
                onRelease: { [weak actions] in
                    actions?.commitWindowSwitcher()
                },
                onCancel: { [weak actions] in
                    actions?.cancelSwitcher()
                }
            )
        )
    }

    private func switchWorkspaceRegistration(
        _ shortcut: ConfiguredShortcut,
        workspace: WorkspaceID,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: shortcut.key,
            name: "Switch to Workspace \(workspace.rawValue)",
            target: shortcut.target,
            onPress: { [weak actions] in
                actions?.switchWorkspace(to: workspace)
            }
        )
    }

    private func moveFocusedWindowRegistration(
        _ shortcut: ConfiguredShortcut,
        workspace: WorkspaceID,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: shortcut.key,
            name: "Move Window to Workspace \(workspace.rawValue)",
            target: shortcut.target,
            onPress: { [weak actions] in
                actions?.moveFocusedWindow(to: workspace)
            }
        )
    }
}
