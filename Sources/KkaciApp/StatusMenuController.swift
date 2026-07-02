import AppKit
import KkaciCore

final class StatusMenuController: NSObject {
    private let axClient: AXClient
    private let controller: WorkspaceController
    private let reloadConfigHandler: () -> Void
    private let accessibilityGrantedHandler: () -> Void
    private let settingsSnapshotProvider: () -> SettingsSnapshot
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let permissionItem = NSMenuItem()
    private let messageItem = NSMenuItem()
    private lazy var debugStatusWindowController = DebugStatusWindowController(
        controller: controller,
        lastMessage: { [weak self] in self?.currentMessage ?? "" }
    )
    private lazy var switcherCoordinator = SwitcherCoordinator(
        controller: controller,
        showMessage: { [weak self] message in
            self?.showMessage(message)
        },
        refreshStatus: { [weak self] in
            self?.refreshSurfaces()
        }
    )
    private var settingsWindowController: SettingsWindowController?
    private var workspaceItems: [String: NSMenuItem] = [:]
    private var renderedWorkspaces: [String] = []
    private var currentMessage = "Ready"
    private var suppressedFocusedWindowID: WindowID?

    init(
        axClient: AXClient,
        controller: WorkspaceController,
        reloadConfigHandler: @escaping () -> Void,
        accessibilityGrantedHandler: @escaping () -> Void,
        settingsSnapshotProvider: @escaping () -> SettingsSnapshot
    ) {
        self.axClient = axClient
        self.controller = controller
        self.reloadConfigHandler = reloadConfigHandler
        self.accessibilityGrantedHandler = accessibilityGrantedHandler
        self.settingsSnapshotProvider = settingsSnapshotProvider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        refreshMenu()
    }

    func updatePermissionStatus(_ isGranted: Bool) {
        permissionItem.title = isGranted ? "Accessibility: Granted" : "Accessibility: Missing"
        refreshMenu()
    }

    func showMessage(_ message: String) {
        currentMessage = message
        messageItem.title = message
        refreshSurfaces()
    }

    func showDebugStatusWindow() {
        debugStatusWindowController.show()
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settingsSnapshotProvider: settingsSnapshotProvider,
                reloadConfigHandler: reloadConfigHandler
            )
        }
        settingsWindowController?.show()
    }

    func stepWindowSwitcher(direction: SwitcherDirection) {
        switcherCoordinator.stepWindow(direction: direction)
    }

    func stepWorkspaceSwitcher(direction: SwitcherDirection) {
        switcherCoordinator.stepWorkspace(direction: direction)
    }

    func commitWindowSwitcher() {
        switcherCoordinator.commitWindowSelection()
    }

    func commitWorkspaceSwitcher() {
        switcherCoordinator.commitWorkspaceSelection()
    }

    func switchToNextWorkspace() {
        switcherCoordinator.cancel()
        perform("Switched to next workspace") {
            _ = try controller.switchToNextWorkspace()
        }
    }

    func switchToPreviousWorkspace() {
        switcherCoordinator.cancel()
        perform("Switched to previous workspace") {
            _ = try controller.switchToPreviousWorkspace()
        }
    }

    func focusNextWindow() {
        switcherCoordinator.cancel()
        showWindowFocusResult(controller.focusNextWindow())
    }

    func focusPreviousWindow() {
        switcherCoordinator.cancel()
        showWindowFocusResult(controller.focusPreviousWindow())
    }

    func switchWorkspace(named workspace: String) {
        switcherCoordinator.cancel()
        perform("Switched to workspace \(workspace)") {
            _ = try controller.switchWorkspace(to: workspace)
        }
    }

    func moveFocusedWindow(to workspace: String) {
        switcherCoordinator.cancel()
        do {
            let result = try controller.moveFocusedWindow(to: workspace)
            if result.workspace != controller.activeWorkspace {
                suppressedFocusedWindowID = result.windowID
            }
            showMessage("Moved \(result.windowID) to workspace \(result.workspace)")
        } catch {
            showMessage("Error: \(error)")
        }
    }

    func syncWorkspaceToFocusedWindow() {
        if let suppressedFocusedWindowID,
           controller.focusedWindowID() == suppressedFocusedWindowID
        {
            self.suppressedFocusedWindowID = nil
            reconcileWindowState()
            return
        }

        suppressedFocusedWindowID = nil
        do {
            switch try controller.syncWorkspaceToFocusedWindow() {
            case .switched(let windowID, let workspace):
                showMessage("Switched to workspace \(workspace) for \(windowID)")
            case .alreadyActive(_, _), .noFocusedWindow, .unmanagedWindow(_):
                refreshSurfaces()
            }
        } catch {
            showMessage("Focus sync failed: \(error)")
        }
    }

    func reconcileWindowState() {
        do {
            _ = try controller.reconcileWindowState()
            refreshSurfaces()
        } catch {
            showMessage("Window reconcile failed: \(error)")
        }
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
                title: "Workspace \(workspace)",
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
        messageItem.title = currentMessage
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

        statusItem.button?.title = "kkaci \(controller.activeWorkspace)"
        for (workspace, item) in workspaceItems {
            item.state = workspace == controller.activeWorkspace ? .on : .off
        }
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

        perform("Created workspace \(input.stringValue)") {
            _ = try controller.createWorkspace(named: input.stringValue)
        }
    }

    @objc private func requestAccessibilityPermission() {
        let isGranted = axClient.ensureAccessibilityPermission(prompt: true)
        updatePermissionStatus(isGranted)
        guard isGranted else {
            showMessage("Grant permission in System Settings")
            return
        }

        accessibilityGrantedHandler()
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        guard let workspace = sender.representedObject as? String else {
            showMessage("Missing workspace")
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

        let result = controller.restoreAllHiddenWindows()
        showMessage("Emergency restored \(result.restored.count), skipped \(result.skipped.count)")
    }

    @objc private func reloadConfig() {
        reloadConfigHandler()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func perform(_ successMessage: String, action: () throws -> Void) {
        do {
            try action()
            showMessage(successMessage)
        } catch {
            showMessage("Error: \(error)")
        }
    }

    private func showWindowFocusResult(_ result: WindowFocusResult) {
        switch result {
        case .focused(let id):
            showMessage("Focused \(id)")
        case .noWindowsInWorkspace(let workspace):
            showMessage("No windows in workspace \(workspace)")
        }
    }
}
