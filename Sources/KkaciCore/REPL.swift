import Foundation

public final class REPL {
    private let controller: WorkspaceController
    private let ensureAccessibilityPermission: (Bool) -> Bool

    public init(
        controller: WorkspaceController,
        ensureAccessibilityPermission: @escaping (Bool) -> Bool
    ) {
        self.controller = controller
        self.ensureAccessibilityPermission = ensureAccessibilityPermission
    }

    public func run() {
        print("kkaci prototype")
        if !ensureAccessibilityPermission(true) {
            print("Accessibility permission is required. Grant it in System Settings, then restart this executable.")
        }
        printHelp()

        while true {
            print("\nkkaci:\(controller.activeWorkspace)> ", terminator: "")
            guard let line = readLine() else {
                print("")
                return
            }

            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let command = parts.first else {
                continue
            }

            do {
                let shouldContinue = try handleCommand(REPLCommand(command), parts: parts)
                if !shouldContinue {
                    return
                }
            } catch {
                print("error: \(error)")
            }
        }
    }
}

private extension REPL {
    private func handleCommand(_ command: REPLCommand, parts: [String]) throws -> Bool {
        switch command {
        case .quit:
            return false
        case let .unknown(raw):
            print("Unknown command: \(raw)")
        case .help, .permission, .list, .focused, .workspaces:
            handleReadCommand(command)
        case .assign, .capture, .switchWorkspace, .nextWorkspace, .previousWorkspace:
            try handleWorkspaceCommand(command, parts: parts)
        case .nextWindow, .previousWindow:
            handleWindowCycleCommand(command, parts: parts)
        case .hide, .restore:
            try handleWindowVisibilityCommand(command, parts: parts)
        }
        return true
    }

    private func handleReadCommand(_ command: REPLCommand) {
        switch command {
        case .help:
            printHelp()
        case .permission:
            print(ensureAccessibilityPermission(true) ? "granted" : "missing")
        case .list:
            printWindows()
        case .focused:
            printFocusedWindow()
        case .workspaces:
            printWorkspaces()
        default:
            return
        }
    }

    private func handleWorkspaceCommand(_ command: REPLCommand, parts: [String]) throws {
        switch command {
        case .assign:
            try assign(parts)
        case .capture:
            try capture(parts)
        case .switchWorkspace:
            try switchWorkspace(parts)
        case .nextWorkspace:
            try switchToNextWorkspace(parts)
        case .previousWorkspace:
            try switchToPreviousWorkspace(parts)
        default:
            return
        }
    }

    private func handleWindowCycleCommand(_ command: REPLCommand, parts: [String]) {
        switch command {
        case .nextWindow:
            focusNextWindow(parts)
        case .previousWindow:
            focusPreviousWindow(parts)
        default:
            return
        }
    }

    private func handleWindowVisibilityCommand(_ command: REPLCommand, parts: [String]) throws {
        switch command {
        case .hide:
            try hide(parts)
        case .restore:
            try restore(parts)
        default:
            return
        }
    }

    private func printHelp() {
        print("""

        commands:
          permission                 check/prompt Accessibility permission
          list | ls                  list AX windows
          focused                    print focused window id
          assign <workspace> [id]    assign focused window or id to workspace
          capture <workspace>        assign all visible windows to workspace
          switch | ws <workspace>    switch workspace
          next-workspace | next-ws    switch to the next configured workspace
          prev-workspace | prev-ws    switch to the previous configured workspace
          next-window | next-win      focus the next window in the active workspace
          prev-window | prev-win      focus the previous window in the active workspace
          hide <id>                  move one window to the hide corner
          restore <id> [id...]       restore and focus workspace-hidden windows
          workspaces                 show current in-memory memberships
          quit | exit                stop
        """)
    }
}

private extension REPL {
    private func printWindows() {
        let result = controller.listWindows()
        printSyncSummary(result.sync)
        let windows = result.windows
        guard !windows.isEmpty else {
            print("No windows found.")
            return
        }

        let focused = controller.focusedWindowID()
        for window in windows {
            let focusMark = window.id == focused ? "*" : " "
            let workspace = controller.membership(for: window.id) ?? "-"
            let hidden = controller.isHiddenByWorkspace(window.id) ? "hidden" : "visible"
            let title = window.title.isEmpty ? "(untitled)" : window.title
            let frame = window.frame.map(formatFrame) ?? "frame=?"
            print(
                "\(focusMark) \(window.id) ws=\(workspace) \(hidden) "
                    + "pid=\(window.app.pid) \(window.app.name) :: \(title) \(frame)"
            )
        }
    }

    private func printFocusedWindow() {
        if let id = controller.focusedWindowID() {
            print(id)
        } else {
            print("No focused window.")
        }
    }

    private func assign(_ parts: [String]) throws {
        guard parts.count == 2 || parts.count == 3 else {
            print("usage: assign <workspace> [id]")
            return
        }

        let workspace = parts[1]
        if parts.count == 3 {
            let id = try parseWindowID(parts[2])
            try controller.assignWindow(id, to: workspace)
            print("assigned \(id) -> \(workspace)")
        } else {
            let id = try controller.assignFocused(to: workspace)
            print("assigned focused \(id) -> \(workspace)")
        }
    }

    private func capture(_ parts: [String]) throws {
        guard parts.count == 2 else {
            print("usage: capture <workspace>")
            return
        }
        let sync = try controller.captureVisibleWindows(into: parts[1])
        printSyncSummary(sync)
        print("captured visible windows -> \(parts[1])")
    }

    private func switchWorkspace(_ parts: [String]) throws {
        guard parts.count == 2 else {
            print("usage: switch <workspace>")
            return
        }
        let sync = try controller.switchWorkspace(to: parts[1])
        printSyncSummary(sync)
        print("active workspace: \(parts[1])")
    }

    private func switchToNextWorkspace(_ parts: [String]) throws {
        guard parts.count == 1 else {
            print("usage: next-workspace")
            return
        }
        let result = try controller.switchToNextWorkspace()
        printSyncSummary(result.sync)
        print("active workspace: \(result.workspace)")
    }

    private func switchToPreviousWorkspace(_ parts: [String]) throws {
        guard parts.count == 1 else {
            print("usage: prev-workspace")
            return
        }
        let result = try controller.switchToPreviousWorkspace()
        printSyncSummary(result.sync)
        print("active workspace: \(result.workspace)")
    }

    private func focusNextWindow(_ parts: [String]) {
        guard parts.count == 1 else {
            print("usage: next-window")
            return
        }
        printWindowFocusResult(controller.focusNextWindow())
    }

    private func focusPreviousWindow(_ parts: [String]) {
        guard parts.count == 1 else {
            print("usage: prev-window")
            return
        }
        printWindowFocusResult(controller.focusPreviousWindow())
    }

    private func hide(_ parts: [String]) throws {
        guard parts.count == 2 else {
            print("usage: hide <id>")
            return
        }
        let id = try parseWindowID(parts[1])
        try controller.hideWindow(id)
        print("hidden \(id)")
    }

    private func restore(_ parts: [String]) throws {
        guard parts.count >= 2 else {
            print("usage: restore <id> [id...]")
            return
        }

        for rawID in parts.dropFirst() {
            let id = try parseWindowID(rawID)
            let result = try controller.restoreWindow(id, focus: true)
            switch result {
            case .restored:
                print("restored and focused \(id)")
            case .alreadyVisible:
                print("already visible, focused \(id)")
            }
        }
    }

    private func printWorkspaces() {
        let result = controller.listWindows()
        printSyncSummary(result.sync)
        let windows = result.windows
        let grouped = Dictionary(grouping: windows) { controller.membership(for: $0.id) ?? "-" }

        let workspaces = (controller.workspaces + Array(grouped.keys).sorted())
            .reduce(into: [String]()) { result, workspace in
                if !result.contains(workspace) {
                    result.append(workspace)
                }
            }

        for workspace in workspaces {
            print(workspace == "-" ? "unassigned:" : "workspace \(workspace):")
            for window in grouped[workspace] ?? [] {
                let title = window.title.isEmpty ? "(untitled)" : window.title
                print("  \(window.id) \(window.app.name) :: \(title)")
            }
        }
    }

    private func printSyncSummary(_ sync: WorkspaceSyncSummary) {
        guard !sync.isEmpty else {
            return
        }

        for (id, workspace) in sync.autoAssigned {
            print("auto-assigned \(id) -> \(workspace)")
        }
        for id in sync.removed {
            print("removed closed/missing window \(id)")
        }
    }

    private func printWindowFocusResult(_ result: WindowFocusResult) {
        switch result {
        case let .focused(id):
            print("focused \(id)")
        case let .noWindowsInWorkspace(workspace):
            print("no windows in workspace \(workspace)")
        }
    }

    private func parseWindowID(_ raw: String) throws -> WindowID {
        guard let id = WindowID(raw) else {
            throw CommandError.invalidWindowID(raw)
        }
        return id
    }

    private func formatFrame(_ frame: WindowFrame) -> String {
        let origin = "x=\(format(frame.origin.x)) y=\(format(frame.origin.y))"
        let size = "w=\(format(frame.size.width)) h=\(format(frame.size.height))"
        return "\(origin) \(size)"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }
}

enum CommandError: Error, CustomStringConvertible {
    case invalidWindowID(String)

    var description: String {
        switch self {
        case let .invalidWindowID(raw):
            "Invalid window id: \(raw)"
        }
    }
}
