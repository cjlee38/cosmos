import AppKit
import CosmosCore

enum AppRuntimeStartup {
    static func run(
        requiresOnboarding: Bool,
        showOnboarding: () -> Void,
        startManagedRuntime: () -> Void
    ) {
        if requiresOnboarding {
            showOnboarding()
        } else {
            startManagedRuntime()
        }
    }
}

final class AppRuntime {
    private let log = Log(category: "runtime")

    private let controller: SpaceController
    private let configRuntime: ConfigRuntime
    private let permissionController: AccessibilityPermissionController
    private let generalSettingsService: GeneralSettingsService
    private let appSettingsStore: AppSettingsStore
    private let onboardingStateStore: OnboardingStateStore
    private let applicationRelauncher: any ApplicationRelaunching
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let previewService: SwitcherPreviewService
    private var windowEventMonitor: WindowEventMonitor?
    private var settingsCoordinator: SettingsCoordinator?
    private var onboardingCoordinator: OnboardingCoordinator?
    private var didBootstrapWindowState = false
    private var didBeginManagedRuntime = false
    private var didShutdown = false

    private lazy var setupRelaunchCoordinator = SetupRelaunchCoordinator(
        stateStore: onboardingStateStore,
        relauncher: applicationRelauncher,
        terminate: { NSApp.terminate(nil) },
        onFailure: { [weak self] error in
            self?.presentSetupRelaunchFailure(error)
        }
    )

    private lazy var terminationSignalMonitor = TerminationSignalMonitor(
        recover: { [weak self] in
            self?.shutdown()
        }
    )

    private lazy var actionController = SpaceActionController(
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
        controller: SpaceController,
        configRuntime: ConfigRuntime,
        permissionController: AccessibilityPermissionController,
        generalSettingsService: GeneralSettingsService,
        appSettingsStore: AppSettingsStore,
        onboardingStateStore: OnboardingStateStore,
        applicationRelauncher: any ApplicationRelaunching,
        keyboardShortcutManager: KeyboardShortcutManager,
        previewService: SwitcherPreviewService
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.permissionController = permissionController
        self.generalSettingsService = generalSettingsService
        self.appSettingsStore = appSettingsStore
        self.onboardingStateStore = onboardingStateStore
        self.applicationRelauncher = applicationRelauncher
        self.keyboardShortcutManager = keyboardShortcutManager
        self.previewService = previewService
    }

    func start() {
        PanicRecovery.install { [weak self] in
            self?.shutdown()
        }
        terminationSignalMonitor.start()

        do {
            try controller.refreshDisplayTopology()
        } catch {
            log.error("Initial display discovery failed: \(String(describing: error))")
        }
        AppRuntimeStartup.run(
            requiresOnboarding: onboardingStateStore.requiresOnboarding,
            showOnboarding: showOnboardingWindow,
            startManagedRuntime: startManagedRuntime
        )
    }

    func shutdown() {
        guard didBootstrapWindowState, !didShutdown else {
            return
        }
        didShutdown = true
        do {
            try controller.restoreHiddenWindowsForShutdown()
        } catch {
            log.error("Hidden-window shutdown restore failed: \(String(describing: error))")
        }
    }

    private func startManagedRuntime() {
        guard !didBeginManagedRuntime else {
            return
        }
        didBeginManagedRuntime = true
        _ = statusMenuController
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
        if let startupSessionStateLoadError = controller.startupSessionStateLoadError,
           bootstrapSucceeded {
            let errorMessage = String(describing: startupSessionStateLoadError)
            log.error("Space session state load failed; using defaults: \(errorMessage)")
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
            refreshSpacePresentation()
            log.info("Config reloaded")
        } catch {
            let errorMessage = String(describing: error)
            log.error("Config reload failed; keeping previous config: \(errorMessage)")
            refreshAllSurfaces()
        }
    }

    private func refreshStatusSurfaces() {
        guard didBeginManagedRuntime else {
            return
        }
        statusMenuController.refreshSurfaces()
    }

    private func refreshAllSurfaces() {
        refreshStatusSurfaces()
        settingsCoordinator?.refresh()
    }
}

private extension AppRuntime {
    func showSettingsWindow() {
        guard !setupRelaunchCoordinator.relaunchInProgress else {
            return
        }
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
        let spaceSettingsService = SpaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actionController,
            runtimeMode: { .deferredUntilStartup },
            refreshAfterChange: { [unowned self] in
                onboardingCoordinator?.refresh()
            }
        )
        return OnboardingCoordinator(
            stateStore: onboardingStateStore,
            generalSettingsService: generalSettingsService,
            spaceSettingsService: spaceSettingsService,
            shortcutRecordingController: ShortcutRecordingController(
                service: spaceSettingsService
            ),
            onComplete: { [unowned self] in
                startManagedRuntime()
                showSettingsWindow()
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
            spaceConfigChanged: { [unowned self] in refreshSpacePresentation() },
            reloadConfig: { [unowned self] in reloadConfig() },
            runSetup: { [unowned self] in runSetupAgain() }
        )
    }

    func runSetupAgain() {
        setupRelaunchCoordinator.relaunch()
    }

    func presentSetupRelaunchFailure(_ error: Error) {
        log.error("Setup relaunch failed: \(String(describing: error))")
        let alert = NSAlert(error: error)
        alert.messageText = "Cosmos Could Not Restart"
        alert.informativeText = "Cosmos is still running. Try Run Setup Again once more."
        alert.runModal()
    }

    func refreshSpacePresentation() {
        previewService.refreshAll()
        actionController.refreshSwitcherContent()
        refreshAllSurfaces()
    }
}

private extension AppRuntime {
    func refreshSwitcherContent() {
        actionController.refreshSwitcherContent()
    }

    func startWindowEventMonitor() {
        guard windowEventMonitor == nil else {
            return
        }

        let monitor = WindowEventMonitor(
            onScreenLockChanged: { [weak self] isLocked in
                self?.windowRuntimeEventHandler.screenLockChanged(isLocked: isLocked)
            },
            onSessionActivityChanged: { [weak self] isActive in
                self?.windowRuntimeEventHandler.sessionActivityChanged(isActive: isActive)
            },
            onSystemSleepChanged: { [weak self] isAwake in
                self?.windowRuntimeEventHandler.systemSleepChanged(isAwake: isAwake)
            },
            onDisplayReconfigurationBegan: { [weak self] in
                self?.windowRuntimeEventHandler.displayReconfigurationBegan()
            },
            onDisplayReconfigurationEnded: { [weak self] in
                self?.windowRuntimeEventHandler.displayReconfigurationEnded()
            },
            onEvents: { [weak self] events in
                self?.windowRuntimeEventHandler.handle(events)
            }
        )
        monitor.start()
        windowEventMonitor = monitor
    }

    @discardableResult
    func bootstrapWindowStateAfterPermission() -> Bool {
        startWindowEventMonitor()
        do {
            let hiddenRecords = try controller.bootstrapWindowState()
            refreshSpacePresentation()
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
            return "Captured visible windows to visible spaces"
        }

        return "Applied \(recordResult.reassigned.count) records, restored \(recordResult.restored.count), "
            + "failed \(recordResult.failed.count)"
    }
}
