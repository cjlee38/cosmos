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
        let result = controller.refreshWindows()
        let focused = controller.focusedWindowID()
        let cgWindowOrder = CGWindowOrderSnapshot()

        var lines: [String] = [
            "kkaci debug status",
            "active workspace: \(controller.activeWorkspace)",
            "active workspaces: \(controller.activeWorkspaces.joined(separator: ", "))",
            "workspaces: \(controller.workspaces.joined(separator: ", "))",
            "latest event: \(eventLog.latestMessage)",
            ""
        ]

        lines.append("monitors:")
        for monitor in controller.monitorSlots {
            let frame = format(monitor.display.frame)
            let main = monitor.display.isMain ? " main" : ""
            let active = controller.activeWorkspace(on: monitor.slot)
            lines.append("  slot=\(monitor.slot)\(main) display=\(monitor.display.id) active=\(active) \(frame)")
        }
        lines.append("")

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
                let monitor = controller.membership(for: window.id)
                    .map { String(controller.monitorSlot(for: $0)) } ?? "-"
                let hidden = controller.isHiddenByWorkspace(window.id) ? "hidden" : "visible"
                let minimized = window.isMinimized ? "minimized" : "normal"
                let title = window.title.isEmpty ? "(untitled)" : window.title
                let frame = window.frame.map(formatFrame) ?? "frame=?"
                let cgOrder = cgWindowOrder.format(window.id)
                let identity = "id=\(window.id) \(cgOrder) ws=\(workspace) monitor=\(monitor)"
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

private struct CGWindowOrderSnapshot {
    private let allIndexByID: [WindowID: Int]
    private let screenIndexByID: [WindowID: Int]

    init() {
        allIndexByID = Self.indexByWindowID(options: [.optionAll, .excludeDesktopElements])
        screenIndexByID = Self.indexByWindowID(options: [.optionOnScreenOnly, .excludeDesktopElements])
    }

    func format(_ id: WindowID) -> String {
        "cgAll=\(format(allIndexByID[id])) cgScreen=\(format(screenIndexByID[id]))"
    }

    private func format(_ index: Int?) -> String {
        index.map(String.init) ?? "-"
    }

    private static func indexByWindowID(options: CGWindowListOption) -> [WindowID: Int] {
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }

        var indexByID: [WindowID: Int] = [:]
        for (index, info) in rawList.enumerated() {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber
            else {
                continue
            }

            indexByID[WindowID(number.uint32Value)] = index
        }
        return indexByID
    }
}
