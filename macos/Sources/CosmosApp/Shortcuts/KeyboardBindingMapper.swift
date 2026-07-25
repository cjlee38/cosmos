import CosmosCore

protocol KeyboardShortcutActionHandling: AnyObject {
    func stepSpaceSwitcher(direction: SwitcherDirection)
    func commitSpaceSwitcher()
    func stepWindowSwitcher(direction: SwitcherDirection, wraps: Bool)
    func commitWindowSwitcher()
    func cancelSwitcher()
    func switchSpace(to space: SpaceID)
    func moveFocusedWindow(to space: SpaceID)
    func centerFocusedWindow()
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
        case .spaceSwitcher:
            spaceSwitcherRegistration(
                shortcut,
                name: "Cycle Space",
                actions: actions
            )
        case .windowSwitcher:
            windowSwitcherRegistration(
                shortcut,
                name: "Cycle Window",
                actions: actions
            )
        case .centerWindow:
            centerWindowRegistration(shortcut, actions: actions)
        case let .switchSpace(space):
            switchSpaceRegistration(shortcut, space: space, actions: actions)
        case let .moveWindow(space):
            moveFocusedWindowRegistration(shortcut, space: space, actions: actions)
        }
    }

    private func spaceSwitcherRegistration(
        _ shortcut: ConfiguredShortcut,
        name: String,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .hold(
            key: shortcut.key,
            name: name,
            target: shortcut.target,
            releaseGroup: "space-switcher",
            actions: .init(
                onPress: { [weak actions] in
                    actions?.stepSpaceSwitcher(direction: .forward)
                },
                onRelease: { [weak actions] in
                    actions?.commitSpaceSwitcher()
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

    private func switchSpaceRegistration(
        _ shortcut: ConfiguredShortcut,
        space: SpaceID,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: shortcut.key,
            name: "Switch to Space \(space.rawValue)",
            target: shortcut.target,
            onPress: { [weak actions] in
                actions?.switchSpace(to: space)
            }
        )
    }

    private func moveFocusedWindowRegistration(
        _ shortcut: ConfiguredShortcut,
        space: SpaceID,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: shortcut.key,
            name: "Move Window to Space \(space.rawValue)",
            target: shortcut.target,
            onPress: { [weak actions] in
                actions?.moveFocusedWindow(to: space)
            }
        )
    }

    private func centerWindowRegistration(
        _ shortcut: ConfiguredShortcut,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: shortcut.key,
            name: "Center Window",
            target: shortcut.target,
            onPress: { [weak actions] in
                actions?.centerFocusedWindow()
            }
        )
    }
}
