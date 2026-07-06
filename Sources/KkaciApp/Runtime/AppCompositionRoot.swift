import KkaciCore

struct AppCompositionRoot {
    func build() -> AppRuntime {
        let axClient = AXClient()
        let registry = WindowRegistry(axClient: axClient)
        let configStore = FileKkaciConfigStore.default
        let recordStore = FileHiddenWindowRecordStore.default
        let controller = WorkspaceController(
            windowSystem: registry,
            displayProvider: DisplayProvider(),
            configStore: configStore,
            recordStore: recordStore
        )
        let thumbnailRefresher = WindowThumbnailRefresher(
            controller: controller,
            thumbnailCache: WindowThumbnailCache(),
            workspaceThumbnailCache: WorkspaceThumbnailCache()
        )
        let keyboardShortcutManager = KeyboardShortcutManager()

        return AppRuntime(
            controller: controller,
            configRuntime: ConfigRuntime(
                configStore: configStore,
                configURL: configStore.url,
                controller: controller,
                keyboardShortcutManager: keyboardShortcutManager,
                keyboardBindingMapper: KeyboardBindingMapper()
            ),
            permissionController: AccessibilityPermissionController(axClient: axClient),
            keyboardShortcutManager: keyboardShortcutManager,
            thumbnailRefresher: thumbnailRefresher
        )
    }
}
