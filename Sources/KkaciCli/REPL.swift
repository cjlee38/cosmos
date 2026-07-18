import Foundation
import KkaciCore

final class REPL {
    private let controller: WorkspaceController
    private let ensureAccessibilityPermission: (Bool) -> Bool
    private let output: (String) -> Void

    init(
        controller: WorkspaceController,
        ensureAccessibilityPermission: @escaping (Bool) -> Bool,
        output: @escaping (String) -> Void = { print($0) }
    ) {
        self.controller = controller
        self.ensureAccessibilityPermission = ensureAccessibilityPermission
        self.output = output
    }

    func run() {
        output("kkaci prototype")
        guard ensureAccessibilityPermission(true) else {
            output("Accessibility permission is required. Grant it in System Settings, then restart this executable.")
            return
        }

        do {
            try controller.bootstrapWindowState()
        } catch {
            output("error: \(error)")
            return
        }

        printHelp()
        while true {
            print("\nkkaci:\(controller.currentWorkspace)> ", terminator: "")
            guard let line = readLine() else {
                output("")
                return
            }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !parts.isEmpty else {
                continue
            }

            do {
                guard try execute(REPLCommand(parts: parts)) else {
                    return
                }
            } catch {
                output("error: \(error)")
            }
        }
    }
}

extension REPL {
    func execute(_ command: REPLCommand) throws -> Bool {
        try handleCommand(command)
    }
}

private extension REPL {
    // Keeping the exhaustive command dispatch in one place is clearer than splitting it into partial switches.
    // swiftlint:disable:next cyclomatic_complexity
    func handleCommand(_ command: REPLCommand) throws -> Bool {
        switch command {
        case .quit:
            return false
        case let .invalidUsage(message):
            output(message)
        case let .unknown(raw):
            output("Unknown command: \(raw)")
        case .help:
            printHelp()
        case .permission:
            output(ensureAccessibilityPermission(true) ? "granted" : "missing")
        case .list:
            try refreshWindowState()
            printWindows()
        case .displays:
            _ = try controller.handleDisplayConfigurationChanged()
            printDisplays()
        case .focused:
            try refreshWindowState()
            printFocusedWindow()
        case .workspaces:
            try refreshWindowState()
            printWorkspaces()
        case let .switchWorkspace(workspace):
            try switchWorkspace(workspace)
        case let .moveWindow(workspace):
            try moveWindow(workspace)
        case .unhideAll:
            try unhideAll()
        }
        return true
    }

    func printHelp() {
        output("""

        commands:
          permission                 check/prompt Accessibility permission
          list | ls                  list managed windows
          displays                   show display slot mappings
          focused                    print cached focused window id
          switch | ws <workspace>    switch workspace
          move <workspace>           move the focused window to workspace
          unhide-all                 restore every workspace-hidden window
          workspaces                 show current in-memory memberships
          quit | exit                stop
        """)
    }

    func refreshWindowState() throws {
        let result = try controller.handleWindowSetChanged()
        printSyncSummary(result.sync)
    }
}

private extension REPL {
    func printWindows() {
        let windows = controller.currentWindows()
        guard !windows.isEmpty else {
            output("No windows found.")
            return
        }

        let focused = controller.cachedFocusedWindowID()
        for window in windows {
            let focusMark = window.id == focused ? "*" : " "
            let workspace = controller.membership(for: window.id) ?? "-"
            let hidden = controller.isHiddenByWorkspace(window.id) ? "hidden" : "visible"
            let title = window.title.isEmpty ? "(untitled)" : window.title
            let frame = window.frame.map(formatFrame) ?? "frame=?"
            output(
                "\(focusMark) \(window.id) ws=\(workspace) \(hidden) "
                    + "pid=\(window.app.pid) \(window.app.name) :: \(title) \(frame)"
            )
        }
    }

    func printFocusedWindow() {
        if let id = controller.cachedFocusedWindowID() {
            output(String(id))
        } else {
            output("No focused window.")
        }
    }

    func printDisplays() {
        let lines = DisplayListFormatter.lines(for: controller.displayTopology)
        guard !lines.isEmpty else {
            output("No displays found.")
            return
        }
        lines.forEach(output)
    }

    func switchWorkspace(_ workspace: String) throws {
        guard let sync = try controller.switchWorkspace(to: workspace) else {
            output("workspace not found; no changes")
            return
        }
        printSyncSummary(sync)
        output("current workspace: \(controller.currentWorkspace)")
    }

    func moveWindow(_ workspace: String) throws {
        guard let result = try controller.moveFocusedWindow(to: workspace) else {
            output("workspace not found; no changes")
            return
        }
        switch result.outcome {
        case .moved:
            output("moved \(result.windowID) -> \(result.workspace)")
        case .alreadyInWorkspace:
            output("already in workspace \(result.workspace); no changes")
        }
    }

    func unhideAll() throws {
        let result = try controller.restoreAllHiddenWindows()
        output(
            "restored \(result.restored.count), unavailable \(result.unavailable.count), "
                + "failed \(result.failed.count)"
        )
    }

    func printWorkspaces() {
        let windows = controller.currentWindows()
        let grouped = Dictionary(grouping: windows) { controller.membership(for: $0.id) ?? "-" }
        let workspaces = (controller.workspaces + Array(grouped.keys).sorted())
            .reduce(into: [String]()) { result, workspace in
                if !result.contains(workspace) {
                    result.append(workspace)
                }
            }

        for workspace in workspaces {
            output(workspace == "-" ? "unassigned:" : "workspace \(workspace):")
            for window in grouped[workspace] ?? [] {
                let title = window.title.isEmpty ? "(untitled)" : window.title
                output("  \(window.id) \(window.app.name) :: \(title)")
            }
        }
    }

    func printSyncSummary(_ sync: WorkspaceSyncSummary) {
        guard !sync.isEmpty else {
            return
        }
        for (id, workspace) in sync.autoAssigned {
            output("auto-assigned \(id) -> \(workspace)")
        }
        for id in sync.removed {
            output("removed closed/missing window \(id)")
        }
    }

    func formatFrame(_ frame: WindowFrame) -> String {
        let origin = "x=\(format(frame.origin.x)) y=\(format(frame.origin.y))"
        let size = "w=\(format(frame.size.width)) h=\(format(frame.size.height))"
        return "\(origin) \(size)"
    }

    func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}
