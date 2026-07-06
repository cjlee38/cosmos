enum REPLCommand {
    case help
    case permission
    case list
    case focused
    case assign
    case capture
    case switchWorkspace
    case nextWorkspace
    case previousWorkspace
    case nextWindow
    case previousWindow
    case hide
    case restore
    case workspaces
    case quit
    case unknown(String)

    private static let aliases: [String: REPLCommand] = [
        "help": .help,
        "?": .help,
        "permission": .permission,
        "list": .list,
        "ls": .list,
        "focused": .focused,
        "assign": .assign,
        "capture": .capture,
        "switch": .switchWorkspace,
        "ws": .switchWorkspace,
        "next-workspace": .nextWorkspace,
        "next-ws": .nextWorkspace,
        "prev-workspace": .previousWorkspace,
        "previous-workspace": .previousWorkspace,
        "prev-ws": .previousWorkspace,
        "next-window": .nextWindow,
        "next-win": .nextWindow,
        "prev-window": .previousWindow,
        "previous-window": .previousWindow,
        "prev-win": .previousWindow,
        "hide": .hide,
        "restore": .restore,
        "workspaces": .workspaces,
        "quit": .quit,
        "exit": .quit
    ]

    init(_ raw: String) {
        self = Self.aliases[raw] ?? .unknown(raw)
    }
}
