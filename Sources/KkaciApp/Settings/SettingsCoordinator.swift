import AppKit
import KkaciCore

final class SettingsCoordinator {
    private let windowController: SettingsWindowController
    private let ownWindowVisibilityChanged: () -> Void

    init(
        controller: WorkspaceController,
        configRuntime: ConfigRuntime,
        generalSettingsService: GeneralSettingsService,
        appSettingsStore: AppSettingsStore,
        actions: any KeyboardShortcutActionHandling,
        appearanceChanged: @escaping () -> Void,
        workspaceConfigChanged: @escaping () -> Void,
        ownWindowVisibilityChanged: @escaping () -> Void,
        ownWindowChanged: @escaping (WindowID) -> Void,
        reloadConfig: @escaping () -> Void
    ) {
        self.ownWindowVisibilityChanged = ownWindowVisibilityChanged

        let workspaceSettingsService = WorkspaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actions,
            refreshAfterChange: workspaceConfigChanged
        )
        let shortcutRecordingController = ShortcutRecordingController(
            service: workspaceSettingsService
        )
        let generalViewController = GeneralSettingsViewController(
            service: generalSettingsService,
            configURLProvider: { configRuntime.configURL },
            configStatusProvider: { configRuntime.status },
            reloadConfigHandler: reloadConfig,
            appSettingsStore: appSettingsStore,
            appSettingsChanged: appearanceChanged
        )
        let switcherViewController = SwitcherSettingsViewController(
            store: appSettingsStore,
            settingsService: workspaceSettingsService,
            shortcutRecordingController: shortcutRecordingController,
            onChange: appearanceChanged
        )
        let workspaceViewController = WorkspaceSettingsViewController(
            service: workspaceSettingsService,
            shortcutRecordingController: shortcutRecordingController
        )

        windowController = SettingsWindowController(
            generalViewController: generalViewController,
            switcherViewController: switcherViewController,
            workspaceViewController: workspaceViewController,
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

    private func didCloseWindow() {
        NSApp.setActivationPolicy(.accessory)
        ownWindowVisibilityChanged()
    }
}
