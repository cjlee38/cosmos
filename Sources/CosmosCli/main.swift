import Foundation
import CosmosCore

private func runREPL() {
    let axClient = AXClient()
    let registry = WindowRegistry(axClient: axClient)
    let displayProvider = DisplayProvider()
    let configStore = FileCosmosConfigStore.default
    let recordStore = FileHiddenWindowRecordStore.default
    let controller = SpaceController(
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

switch CLIInvocation(arguments: Array(CommandLine.arguments.dropFirst())) {
case .displays:
    do {
        let topology = try MonitorSlotResolver(displayProvider: DisplayProvider()).topology()
        let lines = DisplayListFormatter.lines(for: topology)
        if lines.isEmpty {
            print("No displays found.")
        } else {
            lines.forEach { print($0) }
        }
    } catch {
        print("error: \(error)")
        exit(EXIT_FAILURE)
    }
case .repl:
    runREPL()
case .invalid:
    print("usage: cosmos [displays]")
    exit(EXIT_FAILURE)
}
