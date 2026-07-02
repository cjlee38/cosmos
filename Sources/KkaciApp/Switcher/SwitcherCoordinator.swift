import AppKit
import KkaciCore

final class SwitcherCoordinator {
    private enum Session {
        case windows(items: [WindowSwitcherItem], selectedIndex: Int, anchorFrame: WindowFrame?)
        case workspaces(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?)
    }

    private let controller: WorkspaceController
    private let contentProvider: SwitcherContentProvider
    private let overlay = SwitcherOverlayWindowController()
    private let eventLog: RuntimeEventLog
    private let refreshStatus: () -> Void
    private var session: Session?

    init(
        controller: WorkspaceController,
        eventLog: RuntimeEventLog,
        refreshStatus: @escaping () -> Void
    ) {
        self.controller = controller
        self.contentProvider = SwitcherContentProvider(controller: controller)
        self.eventLog = eventLog
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
        let windows = controller.currentWindows().windows
        let items = contentProvider.windowItems(in: controller.activeWorkspace, from: windows)
        let anchorFrame = contentProvider.overlayAnchorFrame(from: windows)

        guard !items.isEmpty else {
            eventLog.record("No windows in workspace \(controller.activeWorkspace)")
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
        let windows = controller.currentWindows().windows
        let anchorFrame = contentProvider.overlayAnchorFrame(from: windows)
        let groups = contentProvider.workspaceGroups(from: windows)

        guard !groups.isEmpty else {
            eventLog.record("No workspaces")
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
            eventLog.record("Focused \(item.id)")
            refreshStatus()
        } catch {
            eventLog.record("Window switch failed: \(error)")
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
            eventLog.record("Switched to workspace \(workspace)")
            refreshStatus()
        } catch {
            eventLog.record("Workspace switch failed: \(error)")
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
