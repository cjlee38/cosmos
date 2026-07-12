import AppKit
import KkaciCore

final class SwitcherCoordinator {
    private let log = Log(category: "switcher")

    private enum Session {
        case windows(selection: SwitcherSession<WindowID>, anchorFrame: WindowFrame?)
        case workspaces(selection: SwitcherSession<String>, anchorFrame: WindowFrame?)
    }

    private let controller: WorkspaceController
    private let contentProvider: SwitcherContentProvider
    private let thumbnailRefresher: WindowThumbnailRefresher
    private let overlay = SwitcherOverlayWindowController()
    private let refreshStatus: () -> Void
    private var session: Session?
    private var sessionGeneration = 0
    private var pendingOverlayPresentation: DispatchWorkItem?
    private var thumbnailViewUpdateScheduled = false

    init(
        controller: WorkspaceController,
        thumbnailRefresher: WindowThumbnailRefresher,
        refreshStatus: @escaping () -> Void
    ) {
        self.controller = controller
        contentProvider = SwitcherContentProvider(
            controller: controller,
            windowThumbnailCache: thumbnailRefresher.windowThumbnailCache,
            workspaceThumbnailCache: thumbnailRefresher.workspaceThumbnailCache,
            applicationIconCache: thumbnailRefresher.applicationIconCache
        )
        self.thumbnailRefresher = thumbnailRefresher
        self.refreshStatus = refreshStatus
        thumbnailRefresher.workspaceThumbnailCache.setUpdateHandler { [weak self] in
            self?.scheduleThumbnailViewUpdate()
        }
    }

    func stepWindow(direction: SwitcherDirection) {
        log("step window direction=\(direction)")
        guard case let .windows(currentSelection, anchorFrame) = session else {
            startWindowSession(direction: direction)
            return
        }

        var selection = currentSelection
        selection.step(direction)
        session = .windows(selection: selection, anchorFrame: anchorFrame)
        updateVisibleSelection()
        if overlay.isOverlayVisible {
            refreshManagedThumbnails(priorityIDs: [selection.selectedItem])
        }
    }

    func stepWorkspace(direction: SwitcherDirection) {
        log("step workspace direction=\(direction)")
        guard case let .workspaces(currentSelection, anchorFrame) = session else {
            startWorkspaceSession(direction: direction)
            return
        }

        var selection = currentSelection
        selection.step(direction)
        session = .workspaces(selection: selection, anchorFrame: anchorFrame)
        updateVisibleSelection()
    }

    func cancel() {
        if session != nil {
            log("cancel session=\(describeSession())")
        }
        endSession()
    }

    func prepareOverlay() {
        overlay.prepare(
            windowCount: controller.currentWindows().windows.count,
            workspaceCount: controller.workspaces.count
        )
    }
}

extension SwitcherCoordinator {
    func commitWindowSelection() {
        guard case let .windows(selection, _) = session else {
            return
        }

        let windowID = selection.selectedItem
        endSession()

        log("commit window id=\(windowID) selected=\(selection.selectedIndex)")
        do {
            try controller.focusWindow(windowID)
            log.info("Focused \(windowID)")
        } catch {
            log.error("Window switch failed: \(String(describing: error))")
        }
    }

    func commitWorkspaceSelection() {
        guard case let .workspaces(selection, _) = session else {
            return
        }

        commitWorkspace(name: selection.selectedItem)
    }
}

private extension SwitcherCoordinator {
    private func startWindowSession(direction: SwitcherDirection) {
        let windows = controller.currentWindows().windows
        let liveWindowIDs = Set(windows.map(\.id))
        let windowIDs = controller
            .windowIDsByMostRecentFocus(in: controller.activeWorkspace)
            .filter(liveWindowIDs.contains)

        guard let selection = SwitcherSession(
            items: windowIDs,
            currentItem: windowIDs.first,
            direction: direction
        ) else {
            log.info("No windows in workspace \(controller.activeWorkspace)")
            return
        }

        let anchorFrame = contentProvider.overlayAnchorFrame(
            from: windows,
            preferredWindowID: windowIDs.first
        )
        beginSession(.windows(selection: selection, anchorFrame: anchorFrame))
        log("start windows count=\(selection.items.count) selected=\(selection.selectedIndex)")
    }

    private func startWorkspaceSession(direction: SwitcherDirection) {
        let windows = controller.currentWindows().windows
        let activeWindowID = controller
            .windowIDsByMostRecentFocus(in: controller.activeWorkspace)
            .first
        let anchorFrame = contentProvider.overlayAnchorFrame(
            from: windows,
            preferredWindowID: activeWindowID
        )

        guard let selection = SwitcherSession(
            items: controller.workspaces,
            currentItem: controller.activeWorkspace,
            direction: direction
        ) else {
            log.info("No workspaces")
            return
        }

        beginSession(.workspaces(selection: selection, anchorFrame: anchorFrame))
        log("start workspaces count=\(selection.items.count) selected=\(selection.selectedIndex)")
    }

    private func beginSession(_ session: Session) {
        endSession()
        self.session = session
        scheduleOverlayPresentation()
    }

    private func endSession() {
        sessionGeneration += 1
        pendingOverlayPresentation?.cancel()
        pendingOverlayPresentation = nil
        session = nil
        overlay.hideOverlay()
    }

    private func commitWorkspace(name: String) {
        endSession()

        log("commit workspace=\(name)")
        do {
            _ = try controller.switchWorkspace(to: name)
            log.info("Switched to workspace \(name)")
            refreshStatus()
        } catch {
            log.error("Workspace switch failed: \(String(describing: error))")
        }
    }
}

private extension SwitcherCoordinator {
    @discardableResult
    private func selectWindow(id: WindowID) -> Bool {
        guard case let .windows(currentSelection, anchorFrame) = session else {
            return false
        }

        var selection = currentSelection
        guard selection.select(id) else {
            return false
        }

        session = .windows(selection: selection, anchorFrame: anchorFrame)
        updateVisibleSelection()
        if overlay.isOverlayVisible {
            refreshManagedThumbnails(priorityIDs: [id])
        }
        return true
    }

    @discardableResult
    private func selectWorkspace(name: String) -> Bool {
        guard case let .workspaces(currentSelection, anchorFrame) = session else {
            return false
        }

        var selection = currentSelection
        guard selection.select(name) else {
            return false
        }

        session = .workspaces(selection: selection, anchorFrame: anchorFrame)
        updateVisibleSelection()
        return true
    }

    private func commitWindow(id: WindowID) {
        guard selectWindow(id: id) else {
            return
        }
        commitWindowSelection()
    }

    private func scheduleOverlayPresentation() {
        let generation = sessionGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            guard sessionGeneration == generation else {
                return
            }

            pendingOverlayPresentation = nil
            presentCurrentSession()
        }
        pendingOverlayPresentation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: workItem)
    }

    private func presentCurrentSession() {
        let windows = controller.currentWindows().windows
        switch session {
        case let .windows(selection, anchorFrame):
            let items = contentProvider.windowItems(withIDs: selection.items, from: windows)
            overlay.showWindowSwitcher(
                items: items,
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectWindow(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitWindow(id: id)
                }
            )
            refreshManagedThumbnails(priorityIDs: [selection.selectedItem])
        case let .workspaces(selection, anchorFrame):
            let groups = orderedWorkspaceGroups(names: selection.items, from: windows)
            overlay.showWorkspaceSwitcher(
                groups: groups,
                selectedName: selection.selectedItem,
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

    private func updateVisibleSelection() {
        guard overlay.isOverlayVisible else {
            return
        }

        switch session {
        case let .windows(selection, _):
            overlay.updateWindowSelection(selectedID: selection.selectedItem)
        case let .workspaces(selection, _):
            overlay.updateWorkspaceSelection(selectedName: selection.selectedItem)
        case nil:
            return
        }
    }

    private func orderedWorkspaceGroups(
        names: [String],
        from windows: [WindowSnapshot]
    ) -> [WorkspaceSwitcherGroup] {
        let groupsByName = Dictionary(
            uniqueKeysWithValues: contentProvider.workspaceGroups(from: windows).map { ($0.name, $0) }
        )
        return names.compactMap { groupsByName[$0] }
    }

    private func refreshManagedThumbnails(priorityIDs: [WindowID]) {
        thumbnailRefresher.refreshWindowThumbnails(
            priorityIDs: priorityIDs,
            onThumbnailUpdated: { [weak self] _ in
                self?.scheduleThumbnailViewUpdate()
            }
        )
    }
}

private extension SwitcherCoordinator {
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
        guard overlay.isOverlayVisible else {
            return
        }

        let windows = controller.currentWindows().windows
        switch session {
        case let .windows(selection, _):
            let items = contentProvider.windowItems(withIDs: selection.items, from: windows)
            overlay.updateWindowSwitcher(items: items)
        case let .workspaces(selection, _):
            let groups = orderedWorkspaceGroups(names: selection.items, from: windows)
            overlay.updateWorkspaceSwitcher(groups: groups)
        case nil:
            return
        }
    }

    private func describeSession() -> String {
        switch session {
        case let .windows(selection, _):
            "windows selected=\(selection.selectedIndex)"
        case let .workspaces(selection, _):
            "workspaces selected=\(selection.selectedIndex)"
        case nil:
            "none"
        }
    }

    private func log(_ message: String) {
        log.trace(message)
    }
}
