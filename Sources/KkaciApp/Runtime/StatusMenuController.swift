import AppKit
import KkaciCore

final class StatusMenuController: NSObject {
    private let log = Log(category: "menu")

    private let controller: WorkspaceController
    private let actions: WorkspaceActionController
    private let appSettingsStore: AppSettingsStore
    private let reloadConfigHandler: () -> Void
    private let showSettingsHandler: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let workspaceItem = NSMenuItem()
    private lazy var debugStatusWindowController = DebugStatusWindowController(
        controller: controller
    )
    private var workspaceItems: [WorkspaceID: NSMenuItem] = [:]
    private var renderedWorkspaceMonitorSlots: [WorkspaceID: MonitorSlot] = [:]
    private var renderedMonitorSlots: [MonitorSlot] = []

    init(
        controller: WorkspaceController,
        actions: WorkspaceActionController,
        appSettingsStore: AppSettingsStore,
        reloadConfigHandler: @escaping () -> Void,
        showSettingsHandler: @escaping () -> Void
    ) {
        self.controller = controller
        self.actions = actions
        self.appSettingsStore = appSettingsStore
        self.reloadConfigHandler = reloadConfigHandler
        self.showSettingsHandler = showSettingsHandler
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        refreshMenu()
    }

    func showDebugStatusWindow() {
        debugStatusWindowController.show()
    }

    func refreshSurfaces() {
        refreshMenu()
        debugStatusWindowController.refresh()
    }

    private func buildMenu() {
        menu.removeAllItems()
        workspaceItems.removeAll()
        renderedWorkspaceMonitorSlots = workspaceMonitorSlots()
        renderedMonitorSlots = displayedMonitorSlots()

        statusItem.button?.title = menuBarTitle()
        statusItem.menu = menu

        buildWorkspaceItems()
        menu.addItem(commandItem(title: "Reload Config", action: #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Settings...", action: #selector(showSettings)))
        menu.addItem(diagnosticsItem())
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Quit Kkaci", action: #selector(quit)))
    }

    private func buildWorkspaceItems() {
        workspaceItem.title = "Workspace: \(controller.currentWorkspace)"
        workspaceItem.isEnabled = false
        menu.addItem(workspaceItem)

        let workspaces = controller.workspaces.compactMap(WorkspaceID.init(rawValue:))
        let workspacesByMonitor = Dictionary(grouping: workspaces) {
            controller.effectiveMonitorSlot(for: $0.rawValue)
        }

        for monitorSlot in displayedMonitorSlots() {
            let monitorItem = NSMenuItem(title: "Monitor \(monitorSlot)", action: nil, keyEquivalent: "")
            monitorItem.isEnabled = false
            monitorItem.indentationLevel = 1
            menu.addItem(monitorItem)

            for workspace in workspacesByMonitor[monitorSlot, default: []] {
                let item = NSMenuItem(
                    title: workspace.rawValue,
                    action: #selector(switchWorkspace(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = workspace
                item.indentationLevel = 2
                workspaceItems[workspace] = item
                menu.addItem(item)
            }
        }
    }

    private func diagnosticsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Diagnostics", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(commandItem(title: "Show Debug Status", action: #selector(showDebugStatus)))
        submenu.addItem(.separator())
        submenu.addItem(commandItem(title: "Emergency Unhide All...", action: #selector(emergencyUnhideAll)))
        item.submenu = submenu
        return item
    }

    private func commandItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func refreshMenu() {
        if renderedMonitorSlots != displayedMonitorSlots()
            || renderedWorkspaceMonitorSlots != workspaceMonitorSlots() {
            buildMenu()
        }

        statusItem.button?.title = menuBarTitle()
        workspaceItem.title = "Workspace: \(controller.currentWorkspace)"
        for (workspace, item) in workspaceItems {
            item.state = controller.isWorkspaceVisible(workspace.rawValue) ? .on : .off
        }
    }

    private func workspaceMonitorSlots() -> [WorkspaceID: MonitorSlot] {
        Dictionary(uniqueKeysWithValues: controller.workspaces.compactMap { rawValue in
            guard let id = WorkspaceID(rawValue: rawValue) else {
                return nil
            }
            return (id, controller.effectiveMonitorSlot(for: rawValue))
        })
    }

    private func displayedMonitorSlots() -> [MonitorSlot] {
        let monitorSlots = controller.displayTopology.monitorSlots.map(\.slot)
        return monitorSlots.isEmpty ? [1] : monitorSlots
    }

    private func menuBarTitle() -> String {
        let workspaces = controller.visibleWorkspaces.sorted {
            controller.effectiveMonitorSlot(for: $0) < controller.effectiveMonitorSlot(for: $1)
        }
        return MenuBarTitleFormatter.title(
            workspaces: workspaces,
            currentWorkspace: controller.currentWorkspace,
            style: appSettingsStore.snapshot().menuBarIconStyle
        )
    }

    @objc private func switchWorkspace(_ sender: NSMenuItem) {
        guard let workspace = sender.representedObject as? WorkspaceID else {
            log.error("Missing workspace for menu item")
            return
        }
        actions.switchWorkspace(to: workspace)
    }

    @objc private func showDebugStatus() {
        showDebugStatusWindow()
    }

    @objc private func showSettings() {
        showSettingsHandler()
    }

    @objc private func emergencyUnhideAll() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Emergency Unhide All"
        alert.informativeText = [
            "Restore all windows currently hidden by kkaci.",
            "Windows from other workspaces may become visible until the next workspace switch."
        ].joined(separator: " ")
        alert.addButton(withTitle: "Unhide All")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        actions.restoreAllHiddenWindows()
    }

    @objc private func reloadConfig() {
        reloadConfigHandler()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

enum MenuBarTitleFormatter {
    static func title(
        workspaces: [String],
        currentWorkspace: String,
        style: MenuBarIconStyle
    ) -> String {
        let contents = workspaces
            .map { workspace in
                workspace == currentWorkspace ? "•\(workspace)" : workspace
            }
            .joined(separator: " | ")

        switch style {
        case .angleBrackets:
            return "<\(contents)>"
        case .squareBrackets:
            return "[\(contents)]"
        }
    }
}
