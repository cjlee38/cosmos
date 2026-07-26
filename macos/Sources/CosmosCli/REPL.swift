import CosmosCore
import Foundation

final class REPL {
    private let controller: SpaceController
    private let ensureAccessibilityPermission: (Bool) -> Bool
    private let output: (String) -> Void

    init(
        controller: SpaceController,
        ensureAccessibilityPermission: @escaping (Bool) -> Bool,
        output: @escaping (String) -> Void = { print($0) }
    ) {
        self.controller = controller
        self.ensureAccessibilityPermission = ensureAccessibilityPermission
        self.output = output
    }

    func run() {
        output("cosmos prototype")
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
            print("\ncosmos:\(controller.currentSpace)> ", terminator: "")
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
        case .spaces:
            try refreshWindowState()
            printSpaces()
        case let .switchSpace(space):
            try switchSpace(space)
        case let .moveWindow(space):
            try moveWindow(space)
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
          switch | sp <space>        switch space
          move <space>               move the focused window to space
          unhide-all                 restore every space-hidden window
          spaces                     show current in-memory memberships
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
            let space = controller.membership(for: window.id) ?? "-"
            let hidden = controller.isHiddenBySpace(window.id) ? "hidden" : "visible"
            let title = window.title.isEmpty ? "(untitled)" : window.title
            let frame = window.frame.map(formatFrame) ?? "frame=?"
            output(
                "\(focusMark) \(window.id) ws=\(space) \(hidden) "
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

    func switchSpace(_ space: String) throws {
        guard let sync = try controller.switchSpace(to: space) else {
            output("space not found; no changes")
            return
        }
        printSyncSummary(sync)
        output("current space: \(controller.currentSpace)")
    }

    func moveWindow(_ space: String) throws {
        guard let result = try controller.moveFocusedWindow(to: space) else {
            output("space not found; no changes")
            return
        }
        switch result.outcome {
        case .moved:
            output("moved \(result.windowID) -> \(result.space)")
        case .alreadyInSpace:
            output("already in space \(result.space); no changes")
        }
    }

    func unhideAll() throws {
        let result = try controller.restoreAllHiddenWindows()
        output(
            "restored \(result.restored.count), unavailable \(result.unavailable.count), "
                + "failed \(result.failed.count)"
        )
    }

    func printSpaces() {
        let windows = controller.currentWindows()
        let grouped = Dictionary(grouping: windows) { controller.membership(for: $0.id) ?? "-" }
        let spaces = (controller.spaces + Array(grouped.keys).sorted())
            .reduce(into: [String]()) { result, space in
                if !result.contains(space) {
                    result.append(space)
                }
            }

        for space in spaces {
            output(space == "-" ? "unassigned:" : "space \(space):")
            for window in grouped[space] ?? [] {
                let title = window.title.isEmpty ? "(untitled)" : window.title
                output("  \(window.id) \(window.app.name) :: \(title)")
            }
        }
    }

    func printSyncSummary(_ sync: SpaceSyncSummary) {
        guard !sync.isEmpty else {
            return
        }
        for (id, space) in sync.autoAssigned {
            output("auto-assigned \(id) -> \(space)")
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
