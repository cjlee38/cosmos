import AppKit
import KkaciCore

final class AppRuntime {
    private let log = Log(category: "runtime")

    private let controller: WorkspaceController
    private let configRuntime: ConfigRuntime
    private let permissionController: AccessibilityPermissionController
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let thumbnailRefresher: WindowThumbnailRefresher
    private var windowEventMonitor: WindowEventMonitor?

    private lazy var statusMenuController = StatusMenuController(
        controller: controller,
        thumbnailRefresher: thumbnailRefresher,
        reloadConfigHandler: { [unowned self] in
            reloadConfig()
        },
        requestAccessibilityPermissionHandler: { [unowned self] in
            requestAccessibilityPermissionFromMenu()
        },
        settingsSnapshotProvider: { [unowned self] in
            settingsSnapshot()
        },
        updateWorkspaceMonitorHandler: { [unowned self] workspace, monitorSlot in
            updateWorkspaceMonitor(workspace, monitorSlot: monitorSlot)
        }
    )

    init(
        controller: WorkspaceController,
        configRuntime: ConfigRuntime,
        permissionController: AccessibilityPermissionController,
        keyboardShortcutManager: KeyboardShortcutManager,
        thumbnailRefresher: WindowThumbnailRefresher
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.permissionController = permissionController
        self.keyboardShortcutManager = keyboardShortcutManager
        self.thumbnailRefresher = thumbnailRefresher
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)

        statusMenuController.showDebugStatusWindow()
        keyboardShortcutManager.start()
        installInitialShortcuts()

        let hasPermission = permissionController.checkAtLaunch()
        statusMenuController.updatePermissionStatus(hasPermission)

        guard hasPermission else {
            log.warning("Accessibility permission required")
            return
        }

        let bootstrapSucceeded = bootstrapWindowStateAfterPermission()
        if let startupConfigLoadError = controller.startupConfigLoadError, bootstrapSucceeded {
            let errorMessage = String(describing: startupConfigLoadError)
            log.error("Config load failed; using defaults until reload: \(errorMessage)")
        }
    }

    func shutdown() {
        controller.restoreHiddenWindowsForShutdown()
    }

    private func installInitialShortcuts() {
        do {
            try configRuntime.installInitialShortcuts(actions: statusMenuController)
        } catch {
            log.error("Hotkey registration failed: \(String(describing: error))")
        }
    }

    private func reloadConfig() {
        do {
            try configRuntime.reload(actions: statusMenuController)
            thumbnailRefresher.refreshAllThumbnails()
            statusMenuController.prepareSwitcher()
            statusMenuController.refreshSurfaces()
            log.info("Config reloaded")
        } catch {
            let errorMessage = String(describing: error)
            log.error("Config reload failed; keeping previous config: \(errorMessage)")
        }
    }

    private func updateWorkspaceMonitor(_ workspace: String, monitorSlot: MonitorSlot) {
        do {
            try configRuntime.updateWorkspaceMonitor(workspace, monitorSlot: monitorSlot)
            thumbnailRefresher.refreshAllThumbnails()
            statusMenuController.refreshSurfaces()
            log.info("Workspace \(workspace) uses monitor \(monitorSlot)")
        } catch {
            log.error("Workspace monitor update failed: \(String(describing: error))")
        }
    }

    private func requestAccessibilityPermissionFromMenu() -> Bool {
        let isGranted = permissionController.requestFromUser()
        if isGranted {
            _ = bootstrapWindowStateAfterPermission()
        }
        return isGranted
    }

    private func startWindowEventMonitor() {
        guard windowEventMonitor == nil else {
            return
        }

        let monitor = WindowEventMonitor(
            onFocusedWindowChanged: { [weak self] in
                self?.statusMenuController.syncWorkspaceToFocusedWindow()
            },
            onWindowSetChanged: { [weak self] in
                self?.statusMenuController.applyExternalWindowSetChange()
            }
        )
        monitor.start()
        windowEventMonitor = monitor
    }

    @discardableResult
    private func bootstrapWindowStateAfterPermission() -> Bool {
        do {
            let bootstrapResult = try controller.bootstrapWindowState(defaultWorkspace: "1")
            startWindowEventMonitor()
            thumbnailRefresher.refreshAllThumbnails()
            statusMenuController.prepareSwitcher()
            statusMenuController.refreshSurfaces()
            let message = bootstrapMessage(for: bootstrapResult.hiddenRecords)
            log.info(message)
            return true
        } catch {
            log.error("Initial window bootstrap failed: \(String(describing: error))")
            return false
        }
    }

    private func bootstrapMessage(for recordResult: HiddenWindowRecordStartupApplyResult) -> String {
        guard !recordResult.reassigned.isEmpty || !recordResult.restored.isEmpty else {
            return "Captured visible windows to active workspaces"
        }

        return "Applied \(recordResult.reassigned.count) records, restored \(recordResult.restored.count)"
    }

    private func settingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            config: controller.currentConfig,
            configURL: configRuntime.configURL,
            activeWorkspace: controller.activeWorkspace,
            activeWorkspaces: controller.activeWorkspaces,
            runtimeWorkspaces: controller.workspaces,
            monitorSlots: controller.monitorSlots,
            monitorSlotsByWorkspace: Dictionary(uniqueKeysWithValues: controller.workspaces.map { workspace in
                (workspace, controller.monitorSlot(for: workspace))
            })
        )
    }
}
