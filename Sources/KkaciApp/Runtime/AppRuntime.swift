import AppKit
import KkaciCore

final class AppRuntime {
    private let log = Log(category: "runtime")

    private let controller: WorkspaceController
    private let configRuntime: ConfigRuntime
    private let permissionController: AccessibilityPermissionController
    private let generalSettingsService: GeneralSettingsService
    private let appSettingsStore: AppSettingsStore
    private let onboardingStateStore: OnboardingStateStore
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let previewService: SwitcherPreviewService
    private var windowEventMonitor: WindowEventMonitor?
    private var settingsCoordinator: SettingsCoordinator?
    private var onboardingCoordinator: OnboardingCoordinator?
    private var didBootstrapWindowState = false

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
        onboardingStateStore: OnboardingStateStore,
        keyboardShortcutManager: KeyboardShortcutManager,
        previewService: SwitcherPreviewService
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.permissionController = permissionController
        self.generalSettingsService = generalSettingsService
        self.appSettingsStore = appSettingsStore
        self.onboardingStateStore = onboardingStateStore
        self.keyboardShortcutManager = keyboardShortcutManager
        self.previewService = previewService
    }

    func start() {
        do {
            try controller.refreshDisplayTopology()
        } catch {
            log.error("Initial display discovery failed: \(String(describing: error))")
        }
        _ = statusMenuController
        guard !onboardingStateStore.requiresOnboarding else {
            showOnboardingWindow()
            return
        }
        startManagedRuntime()
    }

    func shutdown() {
        guard didBootstrapWindowState else {
            return
        }
        do {
            try controller.restoreHiddenWindowsForShutdown()
        } catch {
            log.error("Hidden-window shutdown restore failed: \(String(describing: error))")
        }
    }

    private func startManagedRuntime() {
        guard !didBootstrapWindowState else {
            return
        }
        startKeyboardShortcuts()

        let hasPermission = permissionController.checkAtLaunch()

        guard hasPermission else {
            log.warning("Accessibility permission required")
            return
        }

        let bootstrapSucceeded = bootstrapWindowStateAfterPermission()
        didBootstrapWindowState = bootstrapSucceeded
        if let startupConfigLoadError = controller.startupConfigLoadError, bootstrapSucceeded {
            let errorMessage = String(describing: startupConfigLoadError)
            log.error("Config load failed; using defaults until reload: \(errorMessage)")
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
        guard !onboardingStateStore.requiresOnboarding else {
            showOnboardingWindow()
            return
        }
        if settingsCoordinator == nil {
            settingsCoordinator = makeSettingsCoordinator()
        }
        settingsCoordinator?.show()
    }

    func showOnboardingWindow() {
        if onboardingCoordinator == nil {
            onboardingCoordinator = makeOnboardingCoordinator()
        }
        onboardingCoordinator?.show()
    }

    func makeOnboardingCoordinator() -> OnboardingCoordinator {
        let workspaceSettingsService = WorkspaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actionController,
            refreshAfterChange: { [unowned self] in
                refreshWorkspacePresentation()
                onboardingCoordinator?.refresh()
            }
        )
        return OnboardingCoordinator(
            stateStore: onboardingStateStore,
            generalSettingsService: generalSettingsService,
            workspaceSettingsService: workspaceSettingsService,
            shortcutRecordingController: ShortcutRecordingController(
                service: workspaceSettingsService
            ),
            onComplete: { [unowned self] in
                refreshStatusSurfaces()
                startManagedRuntime()
            }
        )
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
            reloadConfig: { [unowned self] in reloadConfig() },
            runSetup: { [unowned self] in runSetupAgain() }
        )
    }

    func runSetupAgain() {
        guard settingsCoordinator?.dismiss() == true else {
            return
        }
        showOnboardingWindow()
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
