import AppKit
import CosmosCore

final class SettingsCoordinator {
    private let windowController: SettingsWindowController
    private let ownWindowVisibilityChanged: () -> Void

    init(
        controller: SpaceController,
        configRuntime: ConfigRuntime,
        generalSettingsService: GeneralSettingsService,
        appSettingsStore: AppSettingsStore,
        actions: any KeyboardShortcutActionHandling,
        appearanceChanged: @escaping () -> Void,
        spaceConfigChanged: @escaping () -> Void,
        ownWindowVisibilityChanged: @escaping () -> Void,
        ownWindowChanged: @escaping (WindowID) -> Void,
        reloadConfig: @escaping () -> Void,
        runSetup: @escaping () -> Void
    ) {
        self.ownWindowVisibilityChanged = ownWindowVisibilityChanged

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
        windowController.onClose = { [weak self] in
            self?.didCloseWindow()
        }
        windowController.onWindowChanged = ownWindowChanged
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        windowController.show()
        ownWindowVisibilityChanged()
    }

    func refresh() {
        windowController.refresh()
    }

    func dismissForWindowReplacement() -> Bool {
        guard windowController.dismiss() else {
            return false
        }
        ownWindowVisibilityChanged()
        return true
    }

    private func didCloseWindow() {
        NSApp.setActivationPolicy(.accessory)
        ownWindowVisibilityChanged()
    }
}
