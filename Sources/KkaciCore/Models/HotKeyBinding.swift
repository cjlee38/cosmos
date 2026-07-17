import Foundation

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
