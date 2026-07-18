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
            self?.refreshRuntimeSurfaces()
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
            self?.refreshRuntimeSurfaces()
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
            refreshAllSurfaces()
            log.info("Config reloaded")
        } catch {
            let errorMessage = String(describing: error)
            log.error("Config reload failed; keeping previous config: \(errorMessage)")
            refreshAllSurfaces()
        }
    }

    private func refreshRuntimeSurfaces() {
        statusMenuController.refreshSurfaces()
    }

    private func refreshAllSurfaces() {
        refreshRuntimeSurfaces()
        settingsWindowController?.refresh()
    }
}

private extension AppRuntime {
    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = makeSettingsWindowController()
        }
        settingsWindowController?.show()
    }

    func makeSettingsWindowController() -> SettingsWindowController {
        SettingsWindowController(
            generalSettingsService: generalSettingsService,
            appSettingsStore: appSettingsStore,
            appearanceChangedHandler: { [unowned self] in refreshRuntimeSurfaces() },
            visibilityChangedHandler: { [unowned self] in handleSettingsVisibilityChanged() },
            workspaceSnapshotProvider: { [unowned self] in workspaceSettingsSnapshot() },
            workspaceMonitorChangedHandler: { [unowned self] workspace, displayID in
                try updateWorkspaceMonitor(workspace, displayID: displayID)
            },
            workspaceAddedHandler: { [unowned self] workspaceIDs, displayID in
                try addWorkspaces(workspaceIDs, displayID: displayID)
            },
            workspaceRemovedHandler: { [unowned self] workspaceID in try removeWorkspace(workspaceID) },
            shortcutRecordingBeganHandler: configRuntime.beginShortcutRecording,
            shortcutRecordingCancelledHandler: configRuntime.cancelShortcutRecording,
            shortcutChangedHandler: { [unowned self] target, shortcut in
                try updateShortcut(shortcut, for: target)
            },
            configURLProvider: { [unowned self] in configRuntime.configURL },
            configStatusProvider: { [unowned self] in configRuntime.status },
            reloadConfigHandler: { [unowned self] in reloadConfig() }
        )
    }

    func workspaceSettingsSnapshot() -> WorkspaceSettingsSnapshot {
        WorkspaceSettingsSnapshot(
            config: configRuntime.settingsConfig,
            monitorSlots: controller.monitorSlots,
            displays: controller.displays,
            isEditable: configRuntime.isSettingsEditable,
            shortcutValidationMessages: configRuntime.shortcutValidationMessages
        )
    }

    func updateShortcut(_ shortcut: String?, for target: ShortcutTarget) throws {
        let result = try configRuntime.updateShortcut(shortcut, for: target, actions: actionController)
        refreshAfterWorkspaceConfigChange()
        switch result {
        case .applied:
            log.info("Updated shortcut to \(shortcut ?? "not set")")
        case let .rejected(error):
            log.warning("Saved shortcut but kept previous runtime config: \(error)")
        }
    }

    func updateWorkspaceMonitor(_ workspace: String, displayID: DisplayID) throws {
        let monitorSlot = try WorkspaceDisplayAssignment.monitorSlot(
            for: displayID,
            monitorSlots: controller.monitorSlots
        )
        let config = try editableConfig().assigningWorkspace(workspace, toMonitorSlot: monitorSlot)
        try updateWorkspaceConfig(config)
        log.info("Assigned workspace \(workspace) to display \(displayID)")
    }

    func addWorkspaces(_ workspaceIDs: [WorkspaceID], displayID: DisplayID) throws {
        let monitorSlot = try WorkspaceDisplayAssignment.monitorSlot(
            for: displayID,
            monitorSlots: controller.monitorSlots
        )
        guard let config = try editableConfig().addingWorkspaces(workspaceIDs, display: monitorSlot) else {
            return
        }
        try updateWorkspaceConfig(config)
        log.info(
            "Added workspaces \(workspaceIDs.map(\.rawValue).joined(separator: ",")) "
                + "to display \(displayID)"
        )
    }

    func removeWorkspace(_ workspaceID: WorkspaceID) throws {
        guard let config = try editableConfig().removingWorkspace(workspaceID) else {
            return
        }
        try updateWorkspaceConfig(config)
        log.info("Removed workspace \(workspaceID.rawValue)")
    }

    func updateWorkspaceConfig(_ config: KkaciConfig) throws {
        let result = try configRuntime.updateConfig(config, actions: actionController)
        refreshAfterWorkspaceConfigChange()
        if case let .rejected(error) = result {
            log.warning("Saved config but kept previous runtime config: \(error)")
        }
    }

    func editableConfig() throws -> KkaciConfig {
        guard let desiredConfig = configRuntime.desiredConfig else {
            throw ConfigEditingUnavailableError()
        }
        return desiredConfig
    }

    func refreshAfterWorkspaceConfigChange() {
        previewService.refreshAll()
        actionController.refreshSwitcherContent()
        refreshAllSurfaces()
    }
}

private extension AppRuntime {
    func handleSettingsVisibilityChanged() {
        guard windowEventMonitor != nil else {
            return
        }
        windowRuntimeEventHandler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ]))
    }

    func refreshSwitcherContent() {
        actionController.refreshSwitcherContent()
    }

    func suppressNextFocusSync(for windowID: WindowID) {
        windowRuntimeEventHandler.suppressNextFocusSync(for: windowID)
    }

    func startWindowEventMonitor() {
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
    func bootstrapWindowStateAfterPermission() -> Bool {
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

    func bootstrapMessage(for recordResult: HiddenWindowRecordStartupApplyResult) -> String {
        guard !recordResult.reassigned.isEmpty || !recordResult.restored.isEmpty else {
            return "Captured visible windows to visible workspaces"
        }

        return "Applied \(recordResult.reassigned.count) records, restored \(recordResult.restored.count)"
    }
}
