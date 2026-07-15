import AppKit
import KkaciCore

final class AppRuntime {
    private let log = Log(category: "runtime")

    private let controller: WorkspaceController
    private let configRuntime: ConfigRuntime
    private let permissionController: AccessibilityPermissionController
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let previewService: SwitcherPreviewService
    private var windowEventMonitor: WindowEventMonitor?

    private lazy var actionController = WorkspaceActionController(
        controller: controller,
        previewService: previewService,
        refreshSurfaces: { [weak self] in
            self?.refreshSurfaces()
        },
        suppressNextFocusSync: { [weak self] windowID in
            self?.suppressNextFocusSync(for: windowID)
        }
    )

    private lazy var windowRuntimeEventHandler = WindowRuntimeEventHandler(
        controller: controller,
        previewService: previewService,
        refreshSwitcherContent: { [weak self] in
            self?.refreshSwitcherContent()
        },
        refreshSurfaces: { [weak self] in
            self?.refreshSurfaces()
        }
    )

    private lazy var statusMenuController = StatusMenuController(
        controller: controller,
        actions: actionController,
        reloadConfigHandler: { [unowned self] in
            reloadConfig()
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
        previewService: SwitcherPreviewService
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.permissionController = permissionController
        self.keyboardShortcutManager = keyboardShortcutManager
        self.previewService = previewService
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)

        statusMenuController.showDebugStatusWindow()
        startKeyboardShortcuts()

        let hasPermission = permissionController.checkAtLaunch()

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
        do {
            try controller.restoreHiddenWindowsForShutdown()
        } catch {
            log.error("Hidden-window shutdown restore failed: \(String(describing: error))")
        }
    }

    private func startKeyboardShortcuts() {
        do {
            try keyboardShortcutManager.start()
            try configRuntime.installInitialShortcuts(actions: actionController)
        } catch {
            log.error("Hotkey registration failed: \(String(describing: error))")
        }
    }

    private func reloadConfig() {
        do {
            try keyboardShortcutManager.start()
            try configRuntime.reload(actions: actionController)
            previewService.refreshAll()
            actionController.refreshSwitcherContent()
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
            previewService.refreshAll()
            actionController.refreshSwitcherContent()
            statusMenuController.refreshSurfaces()
            log.info("Workspace \(workspace) uses monitor \(monitorSlot)")
        } catch {
            log.error("Workspace monitor update failed: \(String(describing: error))")
        }
    }

    private func refreshSurfaces() {
        statusMenuController.refreshSurfaces()
    }

    private func refreshSwitcherContent() {
        actionController.refreshSwitcherContent()
    }

    private func suppressNextFocusSync(for windowID: WindowID) {
        windowRuntimeEventHandler.suppressNextFocusSync(for: windowID)
    }

    private func startWindowEventMonitor() {
        guard windowEventMonitor == nil else {
            return
        }

        let monitor = WindowEventMonitor { [weak self] events in
            self?.windowRuntimeEventHandler.handle(events)
        }
        monitor.start()
        windowEventMonitor = monitor
    }

    @discardableResult
    private func bootstrapWindowStateAfterPermission() -> Bool {
        do {
            let hiddenRecords = try controller.bootstrapWindowState(defaultWorkspace: "1")
            startWindowEventMonitor()
            previewService.refreshAll()
            actionController.refreshSwitcherContent()
            statusMenuController.refreshSurfaces()
            let message = bootstrapMessage(for: hiddenRecords)
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
