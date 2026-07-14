import Foundation
import KkaciCore

let axClient = AXClient()
let registry = WindowRegistry(axClient: axClient)
let displayProvider = DisplayProvider()
let configStore = FileKkaciConfigStore.default
let recordStore = FileHiddenWindowRecordStore.default
let controller = WorkspaceController(
    windowSystem: registry,
    displayProvider: displayProvider,
    configStore: configStore,
    recordStore: recordStore
)

if let configLoadError = controller.startupConfigLoadError {
    print("warning: failed to load config.toml; using defaults: \(configLoadError)")
}

defer {
    do {
        try controller.restoreHiddenWindowsForShutdown()
    } catch {
        print("warning: failed to restore hidden windows during shutdown: \(error)")
    }
}

REPL(
    controller: controller,
    ensureAccessibilityPermission: axClient.ensureAccessibilityPermission(prompt:)
).run()
