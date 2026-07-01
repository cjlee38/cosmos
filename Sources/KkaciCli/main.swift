import Foundation
import KkaciCore

let axClient = AXClient()
let registry = WindowRegistry(axClient: axClient)
let displayProvider = DisplayProvider()
let controller = WorkspaceController(
    windowSystem: registry,
    displayProvider: displayProvider
)

REPL(axClient: axClient, controller: controller).run()
