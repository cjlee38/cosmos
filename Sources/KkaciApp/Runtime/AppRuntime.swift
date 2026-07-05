import AppKit
import KkaciCore

final class AppRuntime {
    private let controller: WorkspaceController
    private let configRuntime: ConfigRuntime
    private let permissionController: AccessibilityPermissionController
    private let keyboardShortcutManager: KeyboardShortcutManager
    private let thumbnailRefresher: WindowThumbnailRefresher
    private let eventLog: RuntimeEventLog
    private var windowEventMonitor: WindowEventMonitor?

    private lazy var statusMenuController = StatusMenuController(
        controller: controller,
        thumbnailRefresher: thumbnailRefresher,
        eventLog: eventLog,
        reloadConfigHandler: { [unowned self] in
            reloadConfig()
        },
        requestAccessibilityPermissionHandler: { [unowned self] in
            requestAccessibilityPermissionFromMenu()
        },
        settingsSnapshotProvider: { [unowned self] in
            settingsSnapshot()
        }
    )

    init(
        controller: WorkspaceController,
        configRuntime: ConfigRuntime,
        permissionController: AccessibilityPermissionController,
        keyboardShortcutManager: KeyboardShortcutManager,
        thumbnailRefresher: WindowThumbnailRefresher,
        eventLog: RuntimeEventLog
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.permissionController = permissionController
        self.keyboardShortcutManager = keyboardShortcutManager
        self.thumbnailRefresher = thumbnailRefresher
        self.eventLog = eventLog
    }

    func start() {
        NSApp.setActivationPolicy(.accessory)

        statusMenuController.showDebugStatusWindow()
        keyboardShortcutManager.start()
        installInitialShortcuts()

        let hasPermission = permissionController.checkAtLaunch()
        statusMenuController.updatePermissionStatus(hasPermission)

        guard hasPermission else {
            eventLog.record("Accessibility permission required")
            return
        }

        let bootstrapSucceeded = bootstrapWindowStateAfterPermission()
        if let startupConfigLoadError = controller.startupConfigLoadError, bootstrapSucceeded {
            eventLog.record("Config load failed; using defaults until reload: \(startupConfigLoadError)")
        }
    }

    func shutdown() {
        controller.restoreHiddenWindowsForShutdown()
    }

    private func installInitialShortcuts() {
        do {
            try configRuntime.installInitialShortcuts(actions: statusMenuController)
        } catch {
            eventLog.record("Hotkey registration failed: \(error)")
        }
    }

    private func reloadConfig() {
        do {
            try configRuntime.reload(actions: statusMenuController)
            thumbnailRefresher.refreshAllThumbnails()
            eventLog.record("Config reloaded")
        } catch {
            eventLog.record("Config reload failed; keeping previous config: \(error)")
        }
    }

    private func requestAccessibilityPermissionFromMenu() -> Bool {
        let isGranted = permissionController.requestFromUser()
        if isGranted {
            _ = bootstrapWindowStateAfterPermission()
        }
        return isGranted
    }

    private func startWindowEventMonitor() {
        guard windowEventMonitor == nil else {
            return
        }

        let monitor = WindowEventMonitor(
            onFocusedWindowChanged: { [weak self] in
                self?.statusMenuController.syncWorkspaceToFocusedWindow()
            },
            onWindowSetChanged: { [weak self] in
                self?.statusMenuController.applyExternalWindowSetChange()
            }
        )
        monitor.start()
        windowEventMonitor = monitor
    }

    @discardableResult
    private func bootstrapWindowStateAfterPermission() -> Bool {
        do {
            let bootstrapResult = try controller.bootstrapWindowState(defaultWorkspace: "1")
            startWindowEventMonitor()
            thumbnailRefresher.refreshAllThumbnails()
            eventLog.record(bootstrapMessage(for: bootstrapResult.hiddenRecords))
            return true
        } catch {
            eventLog.record("Initial window bootstrap failed: \(error)")
            return false
        }
    }

    private func bootstrapMessage(for recordResult: HiddenWindowRecordStartupApplyResult) -> String {
        guard !recordResult.reassigned.isEmpty || !recordResult.restored.isEmpty else {
            return "Captured visible windows to active workspaces"
        }

        return "Applied \(recordResult.reassigned.count) records, restored \(recordResult.restored.count)"
    }

    private func settingsSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            config: controller.currentConfig,
            configURL: configRuntime.configURL,
            activeWorkspace: controller.activeWorkspace,
            activeWorkspaces: controller.activeWorkspaces,
            runtimeWorkspaces: controller.workspaces,
            monitorSlotsByWorkspace: Dictionary(uniqueKeysWithValues: controller.workspaces.map { workspace in
                (workspace, controller.monitorSlot(for: workspace))
            })
        )
    }

}
