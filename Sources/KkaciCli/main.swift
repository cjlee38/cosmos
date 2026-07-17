import Foundation
import KkaciCore

private func runREPL() {
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
        print("warning: failed to load config.yaml; using defaults: \(configLoadError)")
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
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["displays"] {
    let topology = MonitorSlotResolver(displayProvider: DisplayProvider()).topology()
    let lines = DisplayListFormatter.lines(for: topology)
    if lines.isEmpty {
        print("No displays found.")
    } else {
        lines.forEach { print($0) }
    }
} else if arguments.isEmpty {
    runREPL()
} else {
    print("usage: kkaci [displays]")
}
