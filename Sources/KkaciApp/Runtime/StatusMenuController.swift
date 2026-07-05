import AppKit
import KkaciCore

final class StatusMenuController: NSObject {
    private let controller: WorkspaceController
    private let thumbnailRefresher: WindowThumbnailRefresher
    private let eventLog: RuntimeEventLog
    private let reloadConfigHandler: () -> Void
    private let requestAccessibilityPermissionHandler: () -> Bool
    private let settingsSnapshotProvider: () -> SettingsSnapshot
    private let updateWorkspaceMonitorHandler: (String, MonitorSlot) -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let permissionItem = NSMenuItem()
    private let messageItem = NSMenuItem()
    private lazy var debugStatusWindowController = DebugStatusWindowController(
        controller: controller,
        eventLog: eventLog
    )
    private lazy var actionController = WorkspaceActionController(
        controller: controller,
        thumbnailRefresher: thumbnailRefresher,
        eventLog: eventLog,
        refreshSurfaces: { [weak self] in
            self?.refreshSurfaces()
        }
    )
    private var settingsWindowController: SettingsWindowController?
    private var workspaceItems: [String: NSMenuItem] = [:]
    private var renderedWorkspaces: [String] = []

    init(
        controller: WorkspaceController,
        thumbnailRefresher: WindowThumbnailRefresher,
        eventLog: RuntimeEventLog,
        reloadConfigHandler: @escaping () -> Void,
        requestAccessibilityPermissionHandler: @escaping () -> Bool,
        settingsSnapshotProvider: @escaping () -> SettingsSnapshot,
        updateWorkspaceMonitorHandler: @escaping (String, MonitorSlot) -> Void
    ) {
        self.controller = controller
        self.thumbnailRefresher = thumbnailRefresher
        self.eventLog = eventLog
        self.reloadConfigHandler = reloadConfigHandler
        self.requestAccessibilityPermissionHandler = requestAccessibilityPermissionHandler
        self.settingsSnapshotProvider = settingsSnapshotProvider
        self.updateWorkspaceMonitorHandler = updateWorkspaceMonitorHandler
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        self.eventLog.onChange = { [weak self] in
            self?.refreshSurfaces()
        }
        buildMenu()
        refreshMenu()
    }

    func updatePermissionStatus(_ isGranted: Bool) {
        permissionItem.title = isGranted ? "Accessibility: Granted" : "Accessibility: Missing"
        refreshMenu()
    }

    func showDebugStatusWindow() {
        debugStatusWindowController.show()
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsSnapshotProvider: settingsSnapshotProvider,
                reloadConfigHandler: reloadConfigHandler,
                updateWorkspaceMonitorHandler: { [weak self] workspace, monitorSlot in
                    self?.updateWorkspaceMonitorHandler(workspace, monitorSlot)
                }
            )
        }
        settingsWindowController?.show()
    }

    func stepWindowSwitcher(direction: SwitcherDirection) {
        actionController.stepWindowSwitcher(direction: direction)
    }

    func stepWorkspaceSwitcher(direction: SwitcherDirection) {
        actionController.stepWorkspaceSwitcher(direction: direction)
    }

    func commitWindowSwitcher() {
        actionController.commitWindowSwitcher()
    }

    func commitWorkspaceSwitcher() {
        actionController.commitWorkspaceSwitcher()
    }

    func switchToNextWorkspace() {
        actionController.switchToNextWorkspace()
    }

    func switchToPreviousWorkspace() {
        actionController.switchToPreviousWorkspace()
    }

    func focusNextWindow() {
        actionController.focusNextWindow()
    }

    func focusPreviousWindow() {
        actionController.focusPreviousWindow()
    }

    func switchWorkspace(named workspace: String) {
        actionController.switchWorkspace(named: workspace)
    }

    func moveFocusedWindow(to workspace: String) {
        actionController.moveFocusedWindow(to: workspace)
    }

    func syncWorkspaceToFocusedWindow() {
        actionController.syncWorkspaceToFocusedWindow()
    }

    func applyExternalWindowSetChange() {
        actionController.applyExternalWindowSetChange()
    }

    private func refreshSurfaces() {
        refreshMenu()
        debugStatusWindowController.refresh()
        settingsWindowController?.refresh()
    }

    private func buildMenu() {
        menu.removeAllItems()
        workspaceItems.removeAll()
        renderedWorkspaces = controller.workspaces

        statusItem.button?.title = "kkaci 1"
        statusItem.menu = menu

        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        let requestPermission = NSMenuItem(
            title: "Request Accessibility Permission",
            action: #selector(requestAccessibilityPermission),
            keyEquivalent: ""
        )
        requestPermission.target = self
        menu.addItem(requestPermission)
        menu.addItem(.separator())

        for workspace in controller.workspaces {
            let item = NSMenuItem(
                title: workspaceMenuTitle(for: workspace),
                action: #selector(switchWorkspace(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = workspace
            workspaceItems[workspace] = item
            menu.addItem(item)
        }

        menu.addItem(commandItem(title: "Add Workspace...", action: #selector(addWorkspace)))
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Next Workspace", action: #selector(nextWorkspace)))
        menu.addItem(commandItem(title: "Previous Workspace", action: #selector(previousWorkspace)))
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Next Window", action: #selector(nextWindow)))
        menu.addItem(commandItem(title: "Previous Window", action: #selector(previousWindow)))
        menu.addItem(.separator())
        let hotKeyHelp = NSMenuItem(title: "Hotkeys: configured in config.toml", action: nil, keyEquivalent: "")
        hotKeyHelp.isEnabled = false
        menu.addItem(hotKeyHelp)
        menu.addItem(commandItem(title: "Reload Config", action: #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Settings...", action: #selector(showSettings)))
        menu.addItem(commandItem(title: "Show Debug Status", action: #selector(showDebugStatus)))
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Emergency Unhide All", action: #selector(emergencyUnhideAll)))
        menu.addItem(.separator())

        messageItem.isEnabled = false
        messageItem.title = eventLog.latestMessage
        menu.addItem(messageItem)
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Quit", action: #selector(quit)))
    }

    private func commandItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshMenu() {
        if renderedWorkspaces != controller.workspaces {
            buildMenu()
        }

        messageItem.title = eventLog.latestMessage
        statusItem.button?.title = "kkaci \(controller.activeWorkspace)"
        for (workspace, item) in workspaceItems {
            item.state = controller.isWorkspaceActive(workspace) ? .on : .off
            item.title = workspaceMenuTitle(for: workspace)
        }
    }

    private func workspaceMenuTitle(for workspace: String) -> String {
        "Workspace \(workspace) -> Monitor \(controller.monitorSlot(for: workspace))"
    }

    @objc private func addWorkspace() {
        NSApp.activate(ignoringOtherApps: true)

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "workspace name"

        let alert = NSAlert()
        alert.messageText = "Add Workspace"
        alert.informativeText = "Enter a workspace name."
        alert.accessoryView = input
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        actionController.createWorkspace(named: input.stringValue)
    }

    @objc private func requestAccessibilityPermission() {
        let isGranted = requestAccessibilityPermissionHandler()
        updatePermissionStatus(isGranted)
        guard isGranted else {
            eventLog.record("Grant permission in System Settings")
            return
        }
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        guard let workspace = sender.representedObject as? String else {
            eventLog.record("Missing workspace")
            return
        }
        switchWorkspace(named: workspace)
    }

    @objc private func nextWorkspace() {
        switchToNextWorkspace()
    }

    @objc private func previousWorkspace() {
        switchToPreviousWorkspace()
    }

    @objc private func nextWindow() {
        focusNextWindow()
    }

    @objc private func previousWindow() {
        focusPreviousWindow()
    }

    @objc private func showDebugStatus() {
        showDebugStatusWindow()
    }

    @objc private func showSettings() {
        showSettingsWindow()
    }

    @objc private func emergencyUnhideAll() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Emergency Unhide All"
        alert.informativeText = "Restore all windows currently hidden by kkaci. Windows from other workspaces may become visible until the next workspace switch."
        alert.addButton(withTitle: "Unhide All")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        actionController.restoreAllHiddenWindows()
    }

    @objc private func reloadConfig() {
        reloadConfigHandler()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

}

extension StatusMenuController: KeyboardShortcutActionHandling {}
