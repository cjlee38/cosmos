import AppKit
import KkaciCore

let axClient = AXClient()
let registry = WindowRegistry(axClient: axClient)
let configStore = FileKkaciConfigStore.default
let snapshotStore = FileHiddenWindowSnapshotStore.default
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
    displayProvider: DisplayProvider(),
    config: config,
    configStore: configStore,
    snapshotStore: snapshotStore,
    isConfigPersistenceEnabled: configLoadError == nil
)

let app = NSApplication.shared
let appDelegate = AppDelegate(
    axClient: axClient,
    controller: controller,
    configStore: configStore,
    config: config,
    configLoadError: configLoadError
)
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
