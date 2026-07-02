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
            return .hold(
                key: binding.key,
                name: "next-workspace",
                releaseGroup: "workspace-switcher",
                onPress: { [weak actions] in
                    actions?.stepWorkspaceSwitcher(direction: .forward)
                },
                onRelease: { [weak actions] in
                    actions?.commitWorkspaceSwitcher()
                }
            )
        case "previous-workspace", "prev-workspace":
            return .hold(
                key: binding.key,
                name: "previous-workspace",
                releaseGroup: "workspace-switcher",
                onPress: { [weak actions] in
                    actions?.stepWorkspaceSwitcher(direction: .backward)
                },
                onRelease: { [weak actions] in
                    actions?.commitWorkspaceSwitcher()
                }
            )
        case "next-window":
            return .hold(
                key: binding.key,
                name: "next-window",
                releaseGroup: "window-switcher",
                onPress: { [weak actions] in
                    actions?.stepWindowSwitcher(direction: .forward)
                },
                onRelease: { [weak actions] in
                    actions?.commitWindowSwitcher()
                }
            )
        case "previous-window", "prev-window":
            return .hold(
                key: binding.key,
                name: "previous-window",
                releaseGroup: "window-switcher",
                onPress: { [weak actions] in
                    actions?.stepWindowSwitcher(direction: .backward)
                },
                onRelease: { [weak actions] in
                    actions?.commitWindowSwitcher()
                }
            )
        case "workspace":
            let workspace = try workspaceName(from: binding)
            return .press(
                key: binding.key,
                name: "workspace \(workspace)",
                onPress: { [weak actions] in
                    actions?.switchWorkspace(named: workspace)
                }
            )
        case "move-window-to-workspace", "move-focused-window-to-workspace":
            let workspace = try workspaceName(from: binding)
            return .press(
                key: binding.key,
                name: "move-window-to-workspace \(workspace)",
                onPress: { [weak actions] in
                    actions?.moveFocusedWindow(to: workspace)
                }
            )
        default:
            throw KeyboardBindingError.unknownCommand(binding.command)
        }
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
        case .unknownCommand(let command):
            return "unknown command \(command)"
        case .missingWorkspace:
            return "workspace command needs a workspace"
        }
    }
}
