import KkaciCore

struct AppCompositionRoot {
    func build() -> AppRuntime {
        let profile = AppProfile.current
        let axClient = AXClient(
            includedOwnWindowIdentifiers: [SettingsWindowController.accessibilityIdentifier]
        )
        let registry = WindowRegistry(axClient: axClient)
        let configStore = FileKkaciConfigStore(url: profile.configURL)
        let recordStore = FileHiddenWindowRecordStore(url: profile.hiddenWindowRecordsURL)
        let controller = WorkspaceController(
            windowSystem: registry,
            displayProvider: DisplayProvider(),
            configStore: configStore,
            recordStore: recordStore
        )
        let previewService = SwitcherPreviewService(
            controller: controller,
            windowThumbnailCache: WindowThumbnailCache(),
            workspaceThumbnailCache: WorkspaceThumbnailCache(),
            applicationIconCache: ApplicationIconCache()
        )
        let keyboardShortcutManager = KeyboardShortcutManager()
        let appSettingsStore = AppSettingsStore()

        return AppRuntime(
            controller: controller,
            configRuntime: ConfigRuntime(
                configStore: configStore,
                configURL: configStore.url,
                controller: controller,
                keyboardShortcutManager: keyboardShortcutManager,
                keyboardBindingMapper: KeyboardBindingMapper(),
                initialLoadError: controller.startupConfigLoadError
            ),
            permissionController: AccessibilityPermissionController(axClient: axClient),
            generalSettingsService: GeneralSettingsService(axClient: axClient),
            appSettingsStore: appSettingsStore,
            keyboardShortcutManager: keyboardShortcutManager,
            previewService: previewService
        )
    }
}
