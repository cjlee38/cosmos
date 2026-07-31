import CosmosCore

struct AppCompositionRoot {
    func build() -> AppRuntime {
        let profile = AppProfile.current
        let axClient = AXClient()
        let registry = WindowRegistry(axClient: axClient)
        let configStore = FileCosmosConfigStore(url: profile.configURL)
        let sessionStateStore = FileSessionStateStore(url: profile.sessionStateURL)
        let controller = SpaceController(
            windowSystem: registry,
            displayProvider: DisplayProvider(),
            configStore: configStore,
            sessionStateStore: sessionStateStore
        )
        let previewService = SwitcherPreviewService(
            controller: controller,
            windowThumbnailCache: WindowThumbnailCache(),
            spaceThumbnailCache: SpaceThumbnailCache(),
            applicationIconCache: ApplicationIconCache()
        )
        let keyboardShortcutManager = KeyboardShortcutManager()
        let appSettingsStore = AppSettingsStore()
        let onboardingStateStore = OnboardingStateStore()

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
            onboardingStateStore: onboardingStateStore,
            applicationRelauncher: WorkspaceApplicationRelauncher(),
            keyboardShortcutManager: keyboardShortcutManager,
            previewService: previewService
        )
    }
}
