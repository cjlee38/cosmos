import CoreGraphics
import Foundation
import CosmosCore

final class DebugStatusRenderer {
    private let controller: SpaceController

    init(controller: SpaceController) {
        self.controller = controller
    }

    func render() -> String {
        let windows = controller.currentWindows()
        let focused = controller.cachedFocusedWindowID()

        var lines: [String] = [
            "cosmos debug status",
            "current space: \(controller.currentSpace)",
            "visible spaces: \(controller.visibleSpaces.joined(separator: ", "))",
            "spaces: \(controller.spaces.joined(separator: ", "))",
            ""
        ]

        lines.append("monitors:")
        for monitor in controller.displayTopology.monitorSlots {
            let frame = format(monitor.display.frame)
            let main = monitor.display.isMain ? " main" : ""
            let visible = controller.visibleSpace(on: monitor.slot)
            lines.append(
                "  slot=\(monitor.slot)\(main) display=\(monitor.display.id) "
                    + "name=\(monitor.display.name) visible=\(visible) \(frame)"
            )
        }
        lines.append("")

        lines.append("windows:")
        if windows.isEmpty {
            lines.append("  (none)")
        } else {
            for (zOrder, window) in windows.enumerated() {
                let marker = window.id == focused ? "*" : " "
                let space = controller.membership(for: window.id) ?? "-"
                let monitor = controller.membership(for: window.id)
                    .map { String(controller.effectiveMonitorSlot(for: $0)) } ?? "-"
                let hidden = controller.isHiddenBySpace(window.id) ? "hidden" : "visible"
                let minimized = window.isMinimized ? "minimized" : "normal"
                let title = window.title.isEmpty ? "(untitled)" : window.title
                let frame = window.frame.map(formatFrame) ?? "frame=?"
                let identity = "id=\(window.id) z=\(zOrder) ws=\(space) monitor=\(monitor)"
                let state = "\(hidden) \(minimized) pid=\(window.app.pid)"
                lines.append("\(marker) \(identity) \(state) \(window.app.name) :: \(title) \(frame)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatFrame(_ frame: WindowFrame) -> String {
        let origin = "x=\(format(frame.origin.x)) y=\(format(frame.origin.y))"
        let size = "w=\(format(frame.size.width)) h=\(format(frame.size.height))"
        return "\(origin) \(size)"
    }

    private func format(_ frame: CGRect) -> String {
        let origin = "x=\(format(frame.origin.x)) y=\(format(frame.origin.y))"
        let size = "w=\(format(frame.size.width)) h=\(format(frame.size.height))"
        return "\(origin) \(size)"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}
