import Foundation

struct SettingsRenderer {
    func render(_ snapshot: SettingsSnapshot) -> String {
        let config = snapshot.config
        var lines: [String] = [
            "kkaci settings",
            "config: \(snapshot.configURL?.path ?? "(not file-backed)")",
            "active workspace: \(snapshot.activeWorkspace)",
            "active workspaces: \(snapshot.activeWorkspaces.joined(separator: ", "))",
            "",
            "runtime workspaces:",
        ]

        for workspace in snapshot.runtimeWorkspaces {
            let marker = snapshot.activeWorkspaces.contains(workspace) ? "*" : " "
            let monitor = snapshot.monitorSlotsByWorkspace[workspace] ?? config.workspaces.monitorSlot(for: workspace)
            lines.append("  \(marker) \(workspace) monitor=\(monitor)")
        }

        lines.append("")
        lines.append("config workspaces:")
        for workspace in config.workspaces.names {
            lines.append("  - \(workspace) monitor=\(config.workspaces.monitorSlot(for: workspace))")
        }

        lines.append("")
        lines.append("hotkeys:")
        if config.bindings.isEmpty {
            lines.append("  (none)")
        } else {
            for binding in config.bindings {
                var line = "  \(binding.key) -> \(binding.command)"
                if let workspace = binding.workspace {
                    line += " \(workspace)"
                }
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }
}
