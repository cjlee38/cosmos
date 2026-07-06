import AppKit
import KkaciCore

final class SwitcherCoordinator {
    private enum Session {
        case windows(items: [WindowSwitcherItem], selectedIndex: Int, anchorFrame: WindowFrame?)
        case workspaces(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?)
    }

    private let controller: WorkspaceController
    private let contentProvider: SwitcherContentProvider
    private let thumbnailRefresher: WindowThumbnailRefresher
    private let overlay = SwitcherOverlayWindowController()
    private let eventLog: RuntimeEventLog
    private let refreshStatus: () -> Void
    private var session: Session?
    private var thumbnailViewUpdateScheduled = false

    init(
        controller: WorkspaceController,
        thumbnailRefresher: WindowThumbnailRefresher,
        eventLog: RuntimeEventLog,
        refreshStatus: @escaping () -> Void
    ) {
        self.controller = controller
        self.contentProvider = SwitcherContentProvider(
            controller: controller,
            windowThumbnailCache: thumbnailRefresher.windowThumbnailCache,
            workspaceThumbnailCache: thumbnailRefresher.workspaceThumbnailCache
        )
        self.thumbnailRefresher = thumbnailRefresher
        self.eventLog = eventLog
        self.refreshStatus = refreshStatus
    }

    func stepWindow(direction: SwitcherDirection) {
        log("step window direction=\(direction)")
        switch session {
        case .windows(let items, let selectedIndex, let anchorFrame):
            let nextIndex = advancedIndex(
                selectedIndex,
                count: items.count,
                direction: direction
            )
            selectWindow(at: nextIndex, items: items, anchorFrame: anchorFrame)
            refreshManagedThumbnails(priorityIDs: selectedWindowIDs(items: items, selectedIndex: nextIndex))
        default:
            startWindowSession(direction: direction)
        }
    }

    func stepWorkspace(direction: SwitcherDirection) {
        log("step workspace direction=\(direction)")
        switch session {
        case .workspaces(let groups, let selectedIndex, let anchorFrame):
            let nextIndex = advancedIndex(
                selectedIndex,
                count: groups.count,
                direction: direction
            )
            selectWorkspace(at: nextIndex, groups: groups, anchorFrame: anchorFrame)
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
        beginWindowSession(items, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
        refreshManagedThumbnails(priorityIDs: selectedWindowIDs(items: items, selectedIndex: selectedIndex))
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
        beginWorkspaceSession(groups, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
    }

    private func beginWindowSession(_ items: [WindowSwitcherItem], selectedIndex: Int, anchorFrame: WindowFrame?) {
        session = .windows(items: items, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
        log("show windows count=\(items.count) selected=\(selectedIndex)")
        presentCurrentSession()
    }

    private func beginWorkspaceSession(_ groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?) {
        session = .workspaces(groups: groups, selectedIndex: selectedIndex, anchorFrame: anchorFrame)
        log("show workspaces count=\(groups.count) selected=\(selectedIndex)")
        presentCurrentSession()
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
            refreshSceneThumbnails(priorityIDs: [item.id])
            refreshStatus()
        } catch {
            eventLog.record("Window switch failed: \(error)")
        }
    }

    func commitWorkspaceSelection() {
        guard case .workspaces(let groups, let selectedIndex, _) = session else {
            return
        }

        guard groups.indices.contains(selectedIndex) else {
            return
        }

        commitWorkspace(name: groups[selectedIndex].name)
    }

    @discardableResult
    private func selectWorkspace(name: String) -> Bool {
        guard case .workspaces(let groups, _, let anchorFrame) = session,
              let index = groups.firstIndex(where: { $0.name == name })
        else {
            return false
        }

        selectWorkspace(at: index, groups: groups, anchorFrame: anchorFrame)
        return true
    }

    private func selectWorkspace(
        at index: Int,
        groups: [WorkspaceSwitcherGroup],
        anchorFrame: WindowFrame?
    ) {
        guard groups.indices.contains(index) else {
            return
        }

        session = .workspaces(groups: groups, selectedIndex: index, anchorFrame: anchorFrame)
        if overlay.isOverlayVisible {
            overlay.updateWorkspaceSelection(selectedName: groups[index].name)
        } else {
            presentCurrentSession()
        }
    }

    private func commitWorkspace(name: String) {
        session = nil
        overlay.hideOverlay()

        log("commit workspace=\(name)")
        do {
            _ = try controller.switchWorkspace(to: name)
            eventLog.record("Switched to workspace \(name)")
            refreshSceneThumbnails()
            refreshStatus()
        } catch {
            eventLog.record("Workspace switch failed: \(error)")
        }
    }

    @discardableResult
    private func selectWindow(id: WindowID) -> Bool {
        guard case .windows(let items, _, let anchorFrame) = session,
              let index = items.firstIndex(where: { $0.id == id })
        else {
            return false
        }

        selectWindow(at: index, items: items, anchorFrame: anchorFrame)
        refreshManagedThumbnails(priorityIDs: [id])
        return true
    }

    private func selectWindow(
        at index: Int,
        items: [WindowSwitcherItem],
        anchorFrame: WindowFrame?
    ) {
        guard items.indices.contains(index) else {
            return
        }

        session = .windows(items: items, selectedIndex: index, anchorFrame: anchorFrame)
        if overlay.isOverlayVisible {
            overlay.updateWindowSelection(selectedID: items[index].id)
        } else {
            presentCurrentSession()
        }
    }

    private func presentCurrentSession() {
        switch session {
        case .windows(let items, let selectedIndex, let anchorFrame):
            overlay.showWindowSwitcher(
                items: items,
                selectedIndex: selectedIndex,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectWindow(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitWindow(id: id)
                }
            )
        case .workspaces(let groups, let selectedIndex, let anchorFrame):
            overlay.showWorkspaceSwitcher(
                groups: groups,
                selectedIndex: selectedIndex,
                anchorFrame: anchorFrame,
                onHover: { [weak self] name in
                    _ = self?.selectWorkspace(name: name)
                },
                onClick: { [weak self] name in
                    self?.commitWorkspace(name: name)
                }
            )
        case nil:
            return
        }
    }

    private func commitWindow(id: WindowID) {
        guard selectWindow(id: id) else {
            return
        }

        commitWindowSelection()
    }

    private func refreshManagedThumbnails(priorityIDs: [WindowID] = []) {
        thumbnailRefresher.refreshWindowThumbnails(
            priorityIDs: priorityIDs,
            onThumbnailUpdated: { [weak self] _ in
                self?.scheduleThumbnailViewUpdate()
            }
        )
    }

    private func refreshSceneThumbnails(priorityIDs: [WindowID] = []) {
        thumbnailRefresher.refreshAllThumbnails(
            priorityIDs: priorityIDs,
            onThumbnailUpdated: { [weak self] _ in
                self?.scheduleThumbnailViewUpdate()
            }
        )
    }

    private func scheduleThumbnailViewUpdate() {
        guard session != nil, !thumbnailViewUpdateScheduled else {
            return
        }

        thumbnailViewUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            thumbnailViewUpdateScheduled = false
            updateActiveSessionThumbnails()
        }
    }

    private func updateActiveSessionThumbnails() {
        switch session {
        case .windows(_, let selectedIndex, let anchorFrame):
            let windows = controller.currentWindows().windows
            let items = contentProvider.windowItems(in: controller.activeWorkspace, from: windows)
            guard !items.isEmpty else {
                cancel()
                return
            }
            session = .windows(
                items: items,
                selectedIndex: clampedIndex(selectedIndex, count: items.count),
                anchorFrame: anchorFrame
            )
            overlay.updateWindowSwitcher(items: items)
        case .workspaces(_, let selectedIndex, let anchorFrame):
            let windows = controller.currentWindows().windows
            let groups = contentProvider.workspaceGroups(from: windows)
            guard !groups.isEmpty else {
                cancel()
                return
            }
            session = .workspaces(
                groups: groups,
                selectedIndex: clampedIndex(selectedIndex, count: groups.count),
                anchorFrame: anchorFrame
            )
            overlay.updateWorkspaceSwitcher(groups: groups)
        case nil:
            return
        }
    }

    private func selectedWindowIDs(items: [WindowSwitcherItem], selectedIndex: Int) -> [WindowID] {
        guard items.indices.contains(selectedIndex) else {
            return []
        }
        return [items[selectedIndex].id]
    }

    private func clampedIndex(_ index: Int, count: Int) -> Int {
        min(max(index, 0), max(count - 1, 0))
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
