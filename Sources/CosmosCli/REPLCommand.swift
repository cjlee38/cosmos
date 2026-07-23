enum REPLCommand: Equatable {
    private static let simpleCommands: [String: REPLCommand] = [
        "help": .help,
        "?": .help,
        "permission": .permission,
        "list": .list,
        "ls": .list,
        "displays": .displays,
        "focused": .focused,
        "spaces": .spaces,
        "quit": .quit,
        "exit": .quit
    ]

    case help
    case permission
    case list
    case displays
    case focused
    case switchSpace(String)
    case moveWindow(String)
    case unhideAll
    case spaces
    case quit
    case invalidUsage(String)
    case unknown(String)

    init(parts: [String]) {
        guard let raw = parts.first else {
            self = .unknown("")
            return
        }

        if let command = Self.simpleCommands[raw] {
            self = command
            return
        }

        switch raw {
        case "switch", "sp":
            self = parts.count == 2
                ? .switchSpace(parts[1])
                : .invalidUsage("usage: switch <space>")
        case "move":
            self = parts.count == 2
                ? .moveWindow(parts[1])
                : .invalidUsage("usage: move <space>")
        case "unhide-all":
            self = parts.count == 1
                ? .unhideAll
                : .invalidUsage("usage: unhide-all")
        default: self = .unknown(raw)
        }
    }
}
