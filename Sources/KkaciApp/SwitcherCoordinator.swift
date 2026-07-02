import AppKit
import KkaciCore

final class SwitcherCoordinator {
    private enum Session {
        case windows(items: [WindowSwitcherItem], selectedIndex: Int, anchorFrame: WindowFrame?)
        case workspaces(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?)
    }

    private let controller: WorkspaceController
    private let overlay = SwitcherOverlayWindowController()
    private let previewProvider = WindowPreviewProvider()
    private let showMessage: (String) -> Void
    private let refreshStatus: () -> Void
    private var session: Session?

    init(
        controller: WorkspaceController,
        showMessage: @escaping (String) -> Void,
        refreshStatus: @escaping () -> Void
    ) {
        self.controller = controller
        self.showMessage = showMessage
        self.refreshStatus = refreshStatus
    }

    func stepWindow(direction: SwitcherDirection) {
        log("step window direction=\(direction)")
        switch session {
        case .windows(let items, let selectedIndex, let anchorFrame):
            showWindows(items, selectedIndex: advancedIndex(
                selectedIndex,
                count: items.count,
                direction: direction
            ), anchorFrame: anchorFrame)
        default:
            startWindowSession(direction: direction)
        }
    }

    func stepWorkspace(direction: SwitcherDirection) {
        log("step workspace direction=\(direction)")
        switch session {
        case .workspaces(let groups, let selectedIndex, let anchorFrame):
            showWorkspaces(groups, selectedIndex: advancedIndex(
                selectedIndex,
                count: groups.count,
                direction: direction
            ), anchorFrame: anchorFrame)
        default:
            startWorkspaceSession(direction: direction)
        }
    }

    func cancel() {
        if session != nil {
            log("cancel session=\(describeSession())")
        }
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
        let anchorFrame = overlayAnchorFrame(from: windows)

        guard !items.isEmpty else {
            showMessage("No windows in workspace \(controller.activeWorkspace)")
            return
        }

        let selectedIndex = initialIndex(
            matching: controller.focusedWindowID(),
            in: items.map(\.id),
            direction: direction
        )
        showWindows(items, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
    }

    private func startWorkspaceSession(direction: SwitcherDirection) {
        do {
            _ = try controller.reconcileWindowState()
        } catch {
            showMessage("Workspace switcher sync failed: \(error)")
            return
        }

        let windows = controller.currentWindows().windows
        let anchorFrame = overlayAnchorFrame(from: windows)
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
        showWorkspaces(groups, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
    }

    private func showWindows(_ items: [WindowSwitcherItem], selectedIndex: Int, anchorFrame: WindowFrame?) {
        session = .windows(items: items, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
        log("show windows count=\(items.count) selected=\(selectedIndex)")
        overlay.showWindowSwitcher(items: items, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
    }

    private func showWorkspaces(_ groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?) {
        session = .workspaces(groups: groups, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
        log("show workspaces count=\(groups.count) selected=\(selectedIndex)")
        overlay.showWorkspaceSwitcher(groups: groups, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
    }

    func commitWindowSelection() {
        guard case .windows(let items, let selectedIndex, _) = session else {
            return
        }

        session = nil
        overlay.hideOverlay()

        guard items.indices.contains(selectedIndex) else {
            return
        }

        let item = items[selectedIndex]
        log("commit window id=\(item.id) selected=\(selectedIndex)")
        do {
            try controller.focusWindow(item.id)
            showMessage("Focused \(item.id)")
            refreshStatus()
        } catch {
            showMessage("Window switch failed: \(error)")
        }
    }

    func commitWorkspaceSelection() {
        guard case .workspaces(let groups, let selectedIndex, _) = session else {
            return
        }

        session = nil
        overlay.hideOverlay()

        guard groups.indices.contains(selectedIndex) else {
            return
        }

        let workspace = groups[selectedIndex].name
        log("commit workspace=\(workspace) selected=\(selectedIndex)")
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

    private func overlayAnchorFrame(from windows: [WindowSnapshot]) -> WindowFrame? {
        if let focusedID = controller.focusedWindowID(),
           let focusedFrame = windows.first(where: { $0.id == focusedID })?.frame
        {
            return focusedFrame
        }

        return windows.first {
            controller.membership(for: $0.id) == controller.activeWorkspace
                && !controller.isHiddenByWorkspace($0.id)
                && !$0.isMinimized
                && $0.frame != nil
        }?.frame
    }

    private func describeSession() -> String {
        switch session {
        case .windows(_, let selectedIndex, _):
            return "windows selected=\(selectedIndex)"
        case .workspaces(_, let selectedIndex, _):
            return "workspaces selected=\(selectedIndex)"
        case nil:
            return "none"
        }
    }

    private func log(_ message: String) {
        NSLog("[kkaci switcher] %@", message)
    }
}
