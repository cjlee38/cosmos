import Foundation
import KkaciCore

let axClient = AXClient()
let registry = WindowRegistry(axClient: axClient)
let displayProvider = DisplayProvider()
let configStore = FileKkaciConfigStore.default
let controller = WorkspaceController(
    windowSystem: registry,
    displayProvider: displayProvider,
    configStore: configStore
)

if let configLoadError = controller.startupConfigLoadError {
    print("warning: failed to load config.toml; using defaults: \(configLoadError)")
}

REPL(
    controller: controller,
    ensureAccessibilityPermission: axClient.ensureAccessibilityPermission(prompt:)
).run()
