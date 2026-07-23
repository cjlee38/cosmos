import AppKit
import CosmosCore

final class StatusMenuController: NSObject {
    private let log = Log(category: "menu")

    private let controller: SpaceController
    private let actions: SpaceActionController
    private let appSettingsStore: AppSettingsStore
    private let reloadConfigHandler: () -> Void
    private let showSettingsHandler: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let spaceItem = NSMenuItem()
    private lazy var debugStatusWindowController = DebugStatusWindowController(
        controller: controller
    )
    private var spaceItems: [SpaceID: NSMenuItem] = [:]
    private var renderedSpaceMonitorSlots: [SpaceID: MonitorSlot] = [:]
    private var renderedMonitorSlots: [MonitorSlot] = []

    init(
        controller: SpaceController,
        actions: SpaceActionController,
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
        spaceItems.removeAll()
        renderedSpaceMonitorSlots = spaceMonitorSlots()
        renderedMonitorSlots = displayedMonitorSlots()

        statusItem.button?.title = menuBarTitle()
        statusItem.menu = menu

        buildSpaceItems()
        menu.addItem(commandItem(title: "Reload Config", action: #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Settings...", action: #selector(showSettings)))
        menu.addItem(diagnosticsItem())
        menu.addItem(.separator())
        menu.addItem(commandItem(title: "Quit Cosmos", action: #selector(quit)))
    }

    private func buildSpaceItems() {
        spaceItem.title = "Space: \(controller.currentSpace)"
        spaceItem.isEnabled = false
        menu.addItem(spaceItem)

        let spaces = controller.spaces.compactMap(SpaceID.init(rawValue:))
        let spacesByMonitor = Dictionary(grouping: spaces) {
            controller.effectiveMonitorSlot(for: $0.rawValue)
        }

        for monitorSlot in displayedMonitorSlots() {
            let monitorItem = NSMenuItem(title: "Monitor \(monitorSlot)", action: nil, keyEquivalent: "")
            monitorItem.isEnabled = false
            monitorItem.indentationLevel = 1
            menu.addItem(monitorItem)

            for space in spacesByMonitor[monitorSlot, default: []] {
                let item = NSMenuItem(
                    title: space.rawValue,
                    action: #selector(switchSpace(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = space
                item.indentationLevel = 2
                spaceItems[space] = item
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
            || renderedSpaceMonitorSlots != spaceMonitorSlots() {
            buildMenu()
        }

        statusItem.button?.title = menuBarTitle()
        spaceItem.title = "Space: \(controller.currentSpace)"
        for (space, item) in spaceItems {
            item.state = controller.isSpaceVisible(space.rawValue) ? .on : .off
        }
    }

    private func spaceMonitorSlots() -> [SpaceID: MonitorSlot] {
        Dictionary(uniqueKeysWithValues: controller.spaces.compactMap { rawValue in
            guard let id = SpaceID(rawValue: rawValue) else {
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
        let spaces = controller.visibleSpaces.sorted {
            controller.effectiveMonitorSlot(for: $0) < controller.effectiveMonitorSlot(for: $1)
        }
        return MenuBarTitleFormatter.title(
            spaces: spaces,
            currentSpace: controller.currentSpace,
            style: appSettingsStore.snapshot().menuBarIconStyle
        )
    }

    @objc private func switchSpace(_ sender: NSMenuItem) {
        guard let space = sender.representedObject as? SpaceID else {
            log.error("Missing space for menu item")
            return
        }
        actions.switchSpace(to: space)
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
            "Restore all windows currently hidden by cosmos.",
            "Windows from other spaces may become visible until the next space switch."
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
        spaces: [String],
        currentSpace: String,
        style: MenuBarIconStyle
    ) -> String {
        let contents = spaces
            .map { space in
                space == currentSpace ? "•\(space)" : space
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
