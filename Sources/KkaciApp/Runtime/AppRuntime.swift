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
    private var settingsCoordinator: SettingsCoordinator?

    private lazy var actionController = WorkspaceActionController(
        controller: controller,
        previewService: previewService,
        appSettingsStore: appSettingsStore,
        refreshStatusSurfaces: { [weak self] in
            self?.refreshStatusSurfaces()
        }
    )

    private lazy var windowRuntimeEventHandler = WindowRuntimeEventHandler(
        controller: controller,
        previewService: previewService,
        refreshSwitcherContent: { [weak self] in
            self?.refreshSwitcherContent()
        },
        refreshStatusSurfaces: { [weak self] in
            self?.refreshStatusSurfaces()
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
            refreshWorkspacePresentation()
            log.info("Config reloaded")
        } catch {
            let errorMessage = String(describing: error)
            log.error("Config reload failed; keeping previous config: \(errorMessage)")
            refreshAllSurfaces()
        }
    }

    private func refreshStatusSurfaces() {
        statusMenuController.refreshSurfaces()
    }

    private func refreshAllSurfaces() {
        refreshStatusSurfaces()
        settingsCoordinator?.refresh()
    }
}

private extension AppRuntime {
    func showSettingsWindow() {
        if settingsCoordinator == nil {
            settingsCoordinator = makeSettingsCoordinator()
        }
        settingsCoordinator?.show()
    }

    func makeSettingsCoordinator() -> SettingsCoordinator {
        SettingsCoordinator(
            controller: controller,
            configRuntime: configRuntime,
            generalSettingsService: generalSettingsService,
            appSettingsStore: appSettingsStore,
            actions: actionController,
            appearanceChanged: { [unowned self] in refreshStatusSurfaces() },
            workspaceConfigChanged: { [unowned self] in refreshWorkspacePresentation() },
            ownWindowVisibilityChanged: { [unowned self] in handleSettingsVisibilityChanged() },
            ownWindowChanged: { [unowned self] windowID in handleSettingsWindowChanged(windowID) },
            reloadConfig: { [unowned self] in reloadConfig() }
        )
    }

    func refreshWorkspacePresentation() {
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
        windowRuntimeEventHandler.handleOwnWindowVisibilityChanged()
    }

    func handleSettingsWindowChanged(_ windowID: WindowID) {
        windowEventMonitor?.scheduleOwnWindowChanged(windowID)
    }

    func refreshSwitcherContent() {
        actionController.refreshSwitcherContent()
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
        startWindowEventMonitor()
        do {
            let hiddenRecords = try controller.bootstrapWindowState()
            refreshWorkspacePresentation()
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

        return "Applied \(recordResult.reassigned.count) records, restored \(recordResult.restored.count), "
            + "failed \(recordResult.failed.count)"
    }
}
