import CosmosCore

final class SettingsCoordinator {
    private let windowController: SettingsWindowController

    init(
        controller: SpaceController,
        configRuntime: ConfigRuntime,
        generalSettingsService: GeneralSettingsService,
        appSettingsStore: AppSettingsStore,
        actions: any KeyboardShortcutActionHandling,
        appearanceChanged: @escaping () -> Void,
        spaceConfigChanged: @escaping () -> Void,
        reloadConfig: @escaping () -> Void,
        runSetup: @escaping () -> Void
    ) {
        let spaceSettingsService = SpaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actions,
            refreshAfterChange: spaceConfigChanged
        )
        let shortcutRecordingController = ShortcutRecordingController(
            service: spaceSettingsService
        )
        let generalViewController = GeneralSettingsViewController(
            service: generalSettingsService,
            configURLProvider: { configRuntime.configURL },
            configStatusProvider: { configRuntime.status },
            reloadConfigHandler: reloadConfig,
            appSettingsStore: appSettingsStore,
            appSettingsChanged: appearanceChanged,
            runSetupHandler: runSetup
        )
        let switcherViewController = SwitcherSettingsViewController(
            store: appSettingsStore,
            settingsService: spaceSettingsService,
            shortcutRecordingController: shortcutRecordingController,
            onChange: appearanceChanged
        )
        let spaceViewController = SpaceSettingsViewController(
            service: spaceSettingsService,
            shortcutRecordingController: shortcutRecordingController
        )
        let windowViewController = WindowSettingsViewController(
            settingsService: spaceSettingsService,
            shortcutRecordingController: shortcutRecordingController
        )

        windowController = SettingsWindowController(
            generalViewController: generalViewController,
            switcherViewController: switcherViewController,
            windowViewController: windowViewController,
            spaceViewController: spaceViewController,
            shortcutRecordingController: shortcutRecordingController
        )
    }

    func show() {
        windowController.show()
    }

    func refresh() {
        windowController.refresh()
    }

    func dismissForWindowReplacement() -> Bool {
        guard windowController.dismiss() else {
            return false
        }
        return true
    }
}
