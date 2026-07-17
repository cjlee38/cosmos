import AppKit
import KkaciCore

final class AppRuntime {
    private let log = Log(category: "runtime")

    private let controller: WorkspaceController
    private let configRuntime: ConfigRuntime
    private let permissionController: AccessibilityPermissionController
    private let generalSettingsService: GeneralSettingsService
    private let appSettingsStore: AppSettingsStore
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let previewService: SwitcherPreviewService
    private var windowEventMonitor: WindowEventMonitor?
    private var settingsWindowController: SettingsWindowController?

    private lazy var actionController = WorkspaceActionController(
        controller: controller,
        previewService: previewService,
        appSettingsStore: appSettingsStore,
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
        appSettingsStore: appSettingsStore,
        reloadConfigHandler: { [unowned self] in
            reloadConfig()
        },
        showSettingsHandler: { [unowned self] in
            showSettingsWindow()
        }
    )

    init(
        controller: WorkspaceController,
        configRuntime: ConfigRuntime,
        permissionController: AccessibilityPermissionController,
        generalSettingsService: GeneralSettingsService,
        appSettingsStore: AppSettingsStore,
        keyboardShortcutManager: KeyboardShortcutManager,
        previewService: SwitcherPreviewService
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.permissionController = permissionController
        self.generalSettingsService = generalSettingsService
        self.appSettingsStore = appSettingsStore
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
            refreshSurfaces()
            log.info("Config reloaded")
        } catch {
            let errorMessage = String(describing: error)
            log.error("Config reload failed; keeping previous config: \(errorMessage)")
        }
    }

    private func refreshSurfaces() {
        statusMenuController.refreshSurfaces()
        settingsWindowController?.refresh()
    }

    private func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                generalSettingsService: generalSettingsService,
                appSettingsStore: appSettingsStore,
                appearanceChangedHandler: { [unowned self] in
                    refreshSurfaces()
                },
                visibilityChangedHandler: { [unowned self] in
                    handleSettingsVisibilityChanged()
                },
                workspaceSnapshotProvider: { [unowned self] in
                    WorkspaceSettingsSnapshot(
                        config: controller.currentConfig,
                        monitorSlots: controller.monitorSlots,
                        displays: controller.displays
                    )
                },
                workspaceMonitorChangedHandler: { [unowned self] workspace, monitorSlot in
                    try updateWorkspaceMonitor(workspace, monitorSlot: monitorSlot)
                },
                workspaceAddedHandler: { [unowned self] workspaceID in
                    try addWorkspace(workspaceID)
                },
                workspaceRemovedHandler: { [unowned self] workspaceID in
                    try removeWorkspace(workspaceID)
                },
                configURLProvider: { [unowned self] in
                    configRuntime.configURL
                },
                configStatusProvider: { [unowned self] in
                    configRuntime.status
                },
                reloadConfigHandler: { [unowned self] in
                    reloadConfig()
                }
            )
        }
        settingsWindowController?.show()
    }

    private func updateWorkspaceMonitor(_ workspace: String, monitorSlot: MonitorSlot) throws {
        try configRuntime.updateWorkspaceMonitor(workspace, monitorSlot: monitorSlot)
        refreshAfterWorkspaceConfigChange()
        log.info("Assigned workspace \(workspace) to monitor \(monitorSlot)")
    }

    private func addWorkspace(_ workspaceID: WorkspaceID) throws {
        guard let config = controller.currentConfig.addingWorkspace(workspaceID) else {
            return
        }
        try updateWorkspaceConfig(config)
        log.info("Added workspace \(workspaceID.rawValue)")
    }

    private func removeWorkspace(_ workspaceID: WorkspaceID) throws {
        guard let config = controller.currentConfig.removingWorkspace(workspaceID) else {
            return
        }
        try updateWorkspaceConfig(config)
        log.info("Removed workspace \(workspaceID.rawValue)")
    }

    private func updateWorkspaceConfig(_ config: KkaciConfig) throws {
        try configRuntime.updateConfig(config, actions: actionController)
        refreshAfterWorkspaceConfigChange()
    }

    private func refreshAfterWorkspaceConfigChange() {
        previewService.refreshAll()
        actionController.refreshSwitcherContent()
        refreshSurfaces()
    }

    private func handleSettingsVisibilityChanged() {
        guard windowEventMonitor != nil else {
            return
        }
        windowRuntimeEventHandler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))
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
            return "Captured visible windows to visible workspaces"
        }

        return "Applied \(recordResult.reassigned.count) records, restored \(recordResult.restored.count)"
    }
}
