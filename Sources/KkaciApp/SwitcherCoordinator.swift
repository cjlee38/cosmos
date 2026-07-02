import AppKit
import KkaciCore

final class SwitcherCoordinator {
    private enum Session {
        case windows(items: [WindowSwitcherItem], selectedIndex: Int)
        case workspaces(groups: [WorkspaceSwitcherGroup], selectedIndex: Int)
    }

    private let controller: WorkspaceController
    private let overlay = SwitcherOverlayWindowController()
    private let previewProvider = WindowPreviewProvider()
    private let showMessage: (String) -> Void
    private let refreshStatus: () -> Void
    private var session: Session?
    private var releaseMonitor: ModifierReleaseMonitor?

    init(
        controller: WorkspaceController,
        showMessage: @escaping (String) -> Void,
        refreshStatus: @escaping () -> Void
    ) {
        self.controller = controller
        self.showMessage = showMessage
        self.refreshStatus = refreshStatus
    }

    func startMonitoringModifierRelease() {
        guard releaseMonitor == nil else {
            return
        }

        let monitor = ModifierReleaseMonitor { [weak self] flags in
            self?.handleFlagsChanged(flags)
        }
        monitor.start()
        releaseMonitor = monitor
    }

    func stepWindow(direction: SwitcherDirection) {
        switch session {
        case .windows(let items, let selectedIndex):
            showWindows(items, selectedIndex: advancedIndex(
                selectedIndex,
                count: items.count,
                direction: direction
            ))
        default:
            startWindowSession(direction: direction)
        }
    }

    func stepWorkspace(direction: SwitcherDirection) {
        switch session {
        case .workspaces(let groups, let selectedIndex):
            showWorkspaces(groups, selectedIndex: advancedIndex(
                selectedIndex,
                count: groups.count,
                direction: direction
            ))
        default:
            startWorkspaceSession(direction: direction)
        }
    }

    func cancel() {
        session = nil
        overlay.hideOverlay()
    }

    private func startWindowSession(direction: SwitcherDirection) {
        do {
            _ = try controller.reconcileWindowState()
        } catch {
            showMessage("Window switcher sync failed: \(error)")
            return
        }

        let windows = controller.currentWindows().windows
        let items = windowItems(in: controller.activeWorkspace, from: windows)

        guard !items.isEmpty else {
            showMessage("No windows in workspace \(controller.activeWorkspace)")
            return
        }

        let selectedIndex = initialIndex(
            matching: controller.focusedWindowID(),
            in: items.map(\.id),
            direction: direction
        )
        showWindows(items, selectedIndex: selectedIndex)
    }

    private func startWorkspaceSession(direction: SwitcherDirection) {
        do {
            _ = try controller.reconcileWindowState()
        } catch {
            showMessage("Workspace switcher sync failed: \(error)")
            return
        }

        let windows = controller.currentWindows().windows
        let groups = controller.workspaces.map { workspace in
            WorkspaceSwitcherGroup(
                name: workspace,
                windows: windowItems(in: workspace, from: windows)
            )
        }

        guard !groups.isEmpty else {
            showMessage("No workspaces")
            return
        }

        let selectedIndex = initialIndex(
            matching: controller.activeWorkspace,
            in: groups.map(\.name),
            direction: direction
        )
        showWorkspaces(groups, selectedIndex: selectedIndex)
    }

    private func showWindows(_ items: [WindowSwitcherItem], selectedIndex: Int) {
        session = .windows(items: items, selectedIndex: selectedIndex)
        overlay.showWindowSwitcher(items: items, selectedIndex: selectedIndex)
    }

    private func showWorkspaces(_ groups: [WorkspaceSwitcherGroup], selectedIndex: Int) {
        session = .workspaces(groups: groups, selectedIndex: selectedIndex)
        overlay.showWorkspaceSwitcher(groups: groups, selectedIndex: selectedIndex)
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        switch session {
        case .windows? where !flags.contains(.option):
            commitWindowSelection()
        case .workspaces? where !flags.contains(.control):
            commitWorkspaceSelection()
        default:
            break
        }
    }

    private func commitWindowSelection() {
        guard case .windows(let items, let selectedIndex) = session else {
            return
        }

        session = nil
        overlay.hideOverlay()

        guard items.indices.contains(selectedIndex) else {
            return
        }

        let item = items[selectedIndex]
        do {
            try controller.focusWindow(item.id)
            showMessage("Focused \(item.id)")
            refreshStatus()
        } catch {
            showMessage("Window switch failed: \(error)")
        }
    }

    private func commitWorkspaceSelection() {
        guard case .workspaces(let groups, let selectedIndex) = session else {
            return
        }

        session = nil
        overlay.hideOverlay()

        guard groups.indices.contains(selectedIndex) else {
            return
        }

        let workspace = groups[selectedIndex].name
        do {
            _ = try controller.switchWorkspace(to: workspace)
            showMessage("Switched to workspace \(workspace)")
            refreshStatus()
        } catch {
            showMessage("Workspace switch failed: \(error)")
        }
    }

    private func initialIndex<T: Equatable>(
        matching current: T?,
        in values: [T],
        direction: SwitcherDirection
    ) -> Int {
        guard !values.isEmpty else {
            return 0
        }
        guard let current, let index = values.firstIndex(of: current) else {
            return 0
        }
        return advancedIndex(index, count: values.count, direction: direction)
    }

    private func advancedIndex(_ index: Int, count: Int, direction: SwitcherDirection) -> Int {
        guard count > 0 else {
            return 0
        }

        switch direction {
        case .forward:
            return (index + 1) % count
        case .backward:
            return (index + count - 1) % count
        }
    }

    private func compareWindows(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        if lhs.app.name == rhs.app.name {
            return lhs.id < rhs.id
        }
        return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
    }

    private func windowItems(in workspace: String, from windows: [WindowSnapshot]) -> [WindowSwitcherItem] {
        windows
            .filter { controller.membership(for: $0.id) == workspace }
            .sorted(by: compareWindows)
            .map {
                previewProvider.makeItem(
                    for: $0,
                    includeThumbnail: !controller.isHiddenByWorkspace($0.id)
                )
            }
    }
}
