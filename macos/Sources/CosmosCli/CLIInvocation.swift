enum CLIInvocation: Equatable {
    case repl
    case displays
    case invalid

    init(arguments: [String]) {
        switch arguments {
        case []:
            self = .repl
        case ["displays"]:
            self = .displays
        default:
            self = .invalid
        }
    }
}
