import AppKit
import KkaciCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let axClient: AXClient
    private let controller: WorkspaceController
    private let config: KkaciConfig
    private let configLoadError: Error?
    private var statusMenuController: StatusMenuController?
    private var hotKeyController: HotKeyController?

    init(
        axClient: AXClient,
        controller: WorkspaceController,
        config: KkaciConfig,
        configLoadError: Error?
    ) {
        self.axClient = axClient
        self.controller = controller
        self.config = config
        self.configLoadError = configLoadError
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusMenuController = StatusMenuController(
            axClient: axClient,
            controller: controller
        )
        self.statusMenuController = statusMenuController
        statusMenuController.showDebugStatusWindow()

        let hotKeyController = HotKeyController(
            statusMenuController: statusMenuController,
            bindings: config.bindings
        )
        hotKeyController.registerConfiguredHotKeys()
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
        } catch {
            captureFailed = true
            statusMenuController.showMessage("Initial capture failed: \(error)")
        }

        if let configLoadError, !captureFailed {
            statusMenuController.showMessage("Config load failed; using defaults: \(configLoadError)")
        }
    }
}
