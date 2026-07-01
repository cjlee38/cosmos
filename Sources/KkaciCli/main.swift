import Foundation
import KkaciCore

let axClient = AXClient()
let registry = WindowRegistry(axClient: axClient)
let displayProvider = DisplayProvider()
let configStore = FileKkaciConfigStore.default
let configLoad = Result { try configStore.load() }
let config: KkaciConfig
let configLoadError: Error?
switch configLoad {
case .success(let loadedConfig):
    config = loadedConfig
    configLoadError = nil
case .failure(let error):
    config = .default
    configLoadError = error
}
let controller = WorkspaceController(
    windowSystem: registry,
    displayProvider: displayProvider,
    config: config,
    configStore: configStore,
    isConfigPersistenceEnabled: configLoadError == nil
)

if let configLoadError {
    print("warning: failed to load config.toml; using defaults: \(configLoadError)")
}
REPL(axClient: axClient, controller: controller).run()
