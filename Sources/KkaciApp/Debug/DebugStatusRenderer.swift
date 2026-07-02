import CoreGraphics
import Foundation
import KkaciCore

final class DebugStatusRenderer {
    private let controller: WorkspaceController
    private let eventLog: RuntimeEventLog

    init(controller: WorkspaceController, eventLog: RuntimeEventLog) {
        self.controller = controller
        self.eventLog = eventLog
    }

    func render() -> String {
        let result = controller.currentWindows()
        let focused = controller.focusedWindowID()

        var lines: [String] = [
            "kkaci debug status",
            "active workspace: \(controller.activeWorkspace)",
            "workspaces: \(controller.workspaces.joined(separator: ", "))",
            "latest event: \(eventLog.latestMessage)",
            "",
        ]

        if !result.sync.isEmpty {
            lines.append("sync:")
            for (id, workspace) in result.sync.autoAssigned {
                lines.append("  auto-assigned \(id) -> \(workspace)")
            }
            for id in result.sync.removed {
                lines.append("  removed \(id)")
            }
            lines.append("")
        }

        lines.append("windows:")
        if result.windows.isEmpty {
            lines.append("  (none)")
        } else {
            for window in result.windows {
                let marker = window.id == focused ? "*" : " "
                let workspace = controller.membership(for: window.id) ?? "-"
                let hidden = controller.isHiddenByWorkspace(window.id) ? "hidden" : "visible"
                let minimized = window.isMinimized ? "minimized" : "normal"
                let title = window.title.isEmpty ? "(untitled)" : window.title
                let frame = window.frame.map(formatFrame) ?? "frame=?"
                lines.append("\(marker) id=\(window.id) ws=\(workspace) \(hidden) \(minimized) pid=\(window.app.pid) \(window.app.name) :: \(title) \(frame)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatFrame(_ frame: WindowFrame) -> String {
        "x=\(format(frame.origin.x)) y=\(format(frame.origin.y)) w=\(format(frame.size.width)) h=\(format(frame.size.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}
