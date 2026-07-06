import CoreGraphics
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
            "monitors:"
        ]

        for monitor in snapshot.monitorSlots {
            let main = monitor.display.isMain ? " main" : ""
            let frame = format(monitor.display.frame)
            let visibleFrame = format(monitor.display.visibleFrame)
            lines.append(
                "  \(monitor.slot)\(main) display=\(monitor.display.id) frame=\(frame) usable=\(visibleFrame)"
            )
        }

        lines += [
            "",
            "runtime workspaces:"
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

    private func format(_ rect: CGRect) -> String {
        let origin = "x=\(format(rect.origin.x)) y=\(format(rect.origin.y))"
        let size = "w=\(format(rect.size.width)) h=\(format(rect.size.height))"
        return "\(origin) \(size)"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}
