import Foundation
import KkaciCore

protocol KeyboardShortcutActionHandling: AnyObject {
    func stepWorkspaceSwitcher(direction: SwitcherDirection)
    func commitWorkspaceSwitcher()
    func stepWindowSwitcher(direction: SwitcherDirection)
    func commitWindowSwitcher()
    func switchWorkspace(named workspace: String)
    func moveFocusedWindow(to workspace: String)
}

final class KeyboardBindingMapper {
    func registrations(
        for bindings: [HotKeyBinding],
        actions: any KeyboardShortcutActionHandling
    ) throws -> [KeyboardShortcutRegistration] {
        try bindings.map { binding in
            try registration(for: binding, actions: actions)
        }
    }

    private func registration(
        for binding: HotKeyBinding,
        actions: any KeyboardShortcutActionHandling
    ) throws -> KeyboardShortcutRegistration {
        switch binding.command.lowercased() {
        case "next-workspace":
            return workspaceSwitcherRegistration(
                binding,
                name: "next-workspace",
                direction: .forward,
                actions: actions
            )
        case "previous-workspace", "prev-workspace":
            return workspaceSwitcherRegistration(
                binding,
                name: "previous-workspace",
                direction: .backward,
                actions: actions
            )
        case "next-window":
            return windowSwitcherRegistration(
                binding,
                name: "next-window",
                direction: .forward,
                actions: actions
            )
        case "previous-window", "prev-window":
            return windowSwitcherRegistration(
                binding,
                name: "previous-window",
                direction: .backward,
                actions: actions
            )
        case "workspace":
            let workspace = try workspaceName(from: binding)
            return switchWorkspaceRegistration(binding, workspace: workspace, actions: actions)
        case "move-window-to-workspace", "move-focused-window-to-workspace":
            let workspace = try workspaceName(from: binding)
            return moveFocusedWindowRegistration(binding, workspace: workspace, actions: actions)
        default:
            throw KeyboardBindingError.unknownCommand(binding.command)
        }
    }

    private func workspaceSwitcherRegistration(
        _ binding: HotKeyBinding,
        name: String,
        direction: SwitcherDirection,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .hold(
            key: binding.key,
            name: name,
            releaseGroup: "workspace-switcher",
            onPress: { [weak actions] in
                actions?.stepWorkspaceSwitcher(direction: direction)
            },
            onRelease: { [weak actions] in
                actions?.commitWorkspaceSwitcher()
            }
        )
    }

    private func windowSwitcherRegistration(
        _ binding: HotKeyBinding,
        name: String,
        direction: SwitcherDirection,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .hold(
            key: binding.key,
            name: name,
            releaseGroup: "window-switcher",
            onPress: { [weak actions] in
                actions?.stepWindowSwitcher(direction: direction)
            },
            onRelease: { [weak actions] in
                actions?.commitWindowSwitcher()
            }
        )
    }

    private func switchWorkspaceRegistration(
        _ binding: HotKeyBinding,
        workspace: String,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: binding.key,
            name: "workspace \(workspace)",
            onPress: { [weak actions] in
                actions?.switchWorkspace(named: workspace)
            }
        )
    }

    private func moveFocusedWindowRegistration(
        _ binding: HotKeyBinding,
        workspace: String,
        actions: any KeyboardShortcutActionHandling
    ) -> KeyboardShortcutRegistration {
        .press(
            key: binding.key,
            name: "move-window-to-workspace \(workspace)",
            onPress: { [weak actions] in
                actions?.moveFocusedWindow(to: workspace)
            }
        )
    }

    private func workspaceName(from binding: HotKeyBinding) throws -> String {
        guard let workspace = binding.workspace?.trimmingCharacters(in: .whitespacesAndNewlines),
              !workspace.isEmpty
        else {
            throw KeyboardBindingError.missingWorkspace
        }
        return workspace
    }
}

private enum KeyboardBindingError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case missingWorkspace

    var description: String {
        switch self {
        case let .unknownCommand(command):
            "unknown command \(command)"
        case .missingWorkspace:
            "workspace command needs a workspace"
        }
    }
}
