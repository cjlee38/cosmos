import AppKit
import KkaciCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let axClient: AXClient
    private let controller: WorkspaceController
    private let configStore: any KkaciConfigStore
    private var config: KkaciConfig
    private let configLoadError: Error?
    private var statusMenuController: StatusMenuController?
    private var hotKeyController: HotKeyController?
    private var windowEventMonitor: WindowEventMonitor?

    init(
        axClient: AXClient,
        controller: WorkspaceController,
        configStore: any KkaciConfigStore,
        config: KkaciConfig,
        configLoadError: Error?
    ) {
        self.axClient = axClient
        self.controller = controller
        self.configStore = configStore
        self.config = config
        self.configLoadError = configLoadError
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusMenuController = StatusMenuController(
            axClient: axClient,
            controller: controller,
            reloadConfigHandler: { [weak self] in
                self?.reloadConfig()
            },
            accessibilityGrantedHandler: { [weak self] in
                self?.startWindowEventMonitor()
            }
        )
        self.statusMenuController = statusMenuController
        statusMenuController.showDebugStatusWindow()

        let hotKeyController = HotKeyController(
            statusMenuController: statusMenuController,
            bindings: config.bindings
        )
        do {
            try hotKeyController.registerConfiguredHotKeys()
        } catch {
            statusMenuController.showMessage("Hotkey registration failed: \(error)")
        }
        self.hotKeyController = hotKeyController

        let hasPermission = axClient.ensureAccessibilityPermission(prompt: true)
        statusMenuController.updatePermissionStatus(hasPermission)

        guard hasPermission else {
            statusMenuController.showMessage("Accessibility permission required")
            return
        }

        var captureFailed = false
        do {
            try statusMenuController.captureVisibleWindowsToDefaultWorkspace()
            startWindowEventMonitor()
        } catch {
            captureFailed = true
            statusMenuController.showMessage("Initial capture failed: \(error)")
        }

        if let configLoadError, !captureFailed {
            statusMenuController.showMessage("Config load failed; using defaults until reload: \(configLoadError)")
        }
    }

    private func reloadConfig() {
        guard let statusMenuController, let hotKeyController else {
            return
        }

        do {
            let loadedConfig = try configStore.load()
            try hotKeyController.replaceBindings(loadedConfig.bindings)
            controller.applyConfig(loadedConfig, enablePersistence: true)
            config = loadedConfig
            statusMenuController.showMessage("Config reloaded")
        } catch {
            statusMenuController.showMessage("Config reload failed; keeping previous config: \(error)")
        }
    }

    private func startWindowEventMonitor() {
        guard windowEventMonitor == nil else {
            return
        }

        let monitor = WindowEventMonitor(
            onFocusedWindowChanged: { [weak self] in
                self?.statusMenuController?.syncWorkspaceToFocusedWindow()
            },
            onWindowSetChanged: { [weak self] in
                self?.statusMenuController?.syncWindowState()
            }
        )
        monitor.start()
        windowEventMonitor = monitor
    }
}
