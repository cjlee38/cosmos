import AppKit
import KkaciCore

final class SwitcherCoordinator {
    private let log = Log(category: "switcher")

    private let controller: WorkspaceController
    private let previewService: SwitcherPreviewService
    private let makeOverlay: () -> any SwitcherOverlayPresenting
    private let refreshStatus: () -> Void
    private var overlay: (any SwitcherOverlayPresenting)?
    private var session: ActiveSwitcherSession?
    private var sessionGeneration = 0
    private var pendingOverlayPresentation: DispatchWorkItem?

    init(
        controller: WorkspaceController,
        previewService: SwitcherPreviewService,
        refreshStatus: @escaping () -> Void,
        overlay: (any SwitcherOverlayPresenting)? = nil,
        makeOverlay: @escaping () -> any SwitcherOverlayPresenting
    ) {
        self.controller = controller
        self.previewService = previewService
        self.refreshStatus = refreshStatus
        self.overlay = overlay
        self.makeOverlay = makeOverlay
        if let overlay {
            configureInteractions(for: overlay)
        }
        previewService.setUpdateHandler { [weak self] update in
            self?.applyPreviewUpdate(update)
        }
    }

    private func configureInteractions(for overlay: any SwitcherOverlayPresenting) {
        overlay.setInteractionHandlers(
            onArrowKey: { [weak self] direction in
                self?.moveSelection(direction)
            },
            onOutsideClick: { [weak self] in
                self?.cancel()
            },
            onWorkspaceKey: { [weak self] key in
                self?.commitWorkspace(forShortcutKey: key) == true
            }
        )
    }

    func stepWindow(direction: SwitcherDirection, wraps: Bool) {
        log.trace("step window direction=\(direction)")
        guard session?.stepWindow(direction, wraps: wraps) == true else {
            startWindowSession(direction: direction)
            return
        }
        updateVisibleSelection()
    }

    func stepWorkspace(direction: SwitcherDirection) {
        log.trace("step workspace direction=\(direction)")
        guard session?.stepWorkspace(direction) == true else {
            startWorkspaceSession(direction: direction)
            return
        }
        updateVisibleSelection()
    }

    func cancel() {
        log.trace("cancel session=\(session?.description ?? "none")")
        endSession()
    }

    func handleContentChanged() {
        reconcileActiveSession()
    }
}

extension SwitcherCoordinator {
    func commitWindowSelection() {
        guard let selection = session?.windowSelection else {
            return
        }

        let windowID = selection.selectedItem
        endSession()

        log.trace("commit window id=\(windowID) selected=\(selection.selectedIndex)")
        do {
            try controller.focusWindow(windowID)
            log.info("Focused \(windowID)")
        } catch {
            log.error("Window switch failed: \(String(describing: error))")
        }
    }

    func commitWorkspaceSelection() {
        guard let selection = session?.workspaceSelection else {
            return
        }

        commitWorkspace(id: selection.selectedItem)
    }
}

private extension SwitcherCoordinator {
    private func startWindowSession(direction: SwitcherDirection) {
        let windows = controller.currentWindows()
        let windowIDs = controller.windows(in: controller.currentWorkspace).map(\.id)

        guard let selection = SwitcherSession(
            items: windowIDs,
            currentItem: windowIDs.first,
            direction: direction
        ) else {
            log.info("No windows in workspace \(controller.currentWorkspace)")
            return
        }

        let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: windowIDs.first)
        beginSession(.windows(selection: selection, anchorFrame: anchorFrame))
        log.trace("start windows count=\(selection.items.count) selected=\(selection.selectedIndex)")
    }

    private func startWorkspaceSession(direction: SwitcherDirection) {
        let windows = controller.currentWindows()
        let activeWindowID = controller.windows(in: controller.currentWorkspace).first?.id
        let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: activeWindowID)

        guard let selection = SwitcherSession(
            items: controller.workspaces,
            currentItem: controller.currentWorkspace,
            direction: direction
        ) else {
            log.info("No workspaces")
            return
        }

        beginSession(.workspaces(selection: selection, anchorFrame: anchorFrame))
        log.trace("start workspaces count=\(selection.items.count) selected=\(selection.selectedIndex)")
    }

    private func beginSession(_ session: ActiveSwitcherSession) {
        endSession()
        self.session = session
        scheduleOverlayPresentation()
    }

    private func endSession() {
        sessionGeneration += 1
        pendingOverlayPresentation?.cancel()
        pendingOverlayPresentation = nil
        session = nil
        overlay?.hideOverlay()
    }

    private func commitWorkspace(id: String) {
        endSession()

        log.trace("commit workspace=\(id)")
        do {
            guard try controller.switchWorkspace(to: id) != nil else { return }
            handleContentChanged()
            log.info("Switched to workspace \(id)")
            refreshStatus()
        } catch {
            log.error("Workspace switch failed: \(String(describing: error))")
        }
    }
}

private extension SwitcherCoordinator {
    @discardableResult
    private func selectWindow(id: WindowID) -> Bool {
        guard session?.selectWindow(id) == true else {
            return false
        }
        updateVisibleSelection()
        return true
    }

    @discardableResult
    private func selectWorkspace(id: String) -> Bool {
        guard session?.selectWorkspace(id) == true else {
            return false
        }
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
            guard let self, sessionGeneration == generation else {
                return
            }

            pendingOverlayPresentation = nil
            presentCurrentSession()
        }
        pendingOverlayPresentation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120), execute: workItem)
    }

    private func presentCurrentSession() {
        let overlay = overlayForPresentation()
        switch session {
        case let .windows(selection, anchorFrame):
            overlay.showWindowSwitcher(
                items: previewService.windowItems(ids: selection.items),
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectWindow(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitWindow(id: id)
                }
            )
            previewService.refresh(
                windowIDs: Set(selection.items),
                workspaceNames: [controller.currentWorkspace],
                priorityIDs: [selection.selectedItem]
            )
        case let .workspaces(selection, anchorFrame):
            overlay.showWorkspaceSwitcher(
                groups: previewService.workspaceGroups(ids: selection.items),
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectWorkspace(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitWorkspace(id: id)
                }
            )
            previewService.refreshAll(
                priorityIDs: controller.windows(in: controller.currentWorkspace).first.map { [$0.id] } ?? []
            )
        case nil:
            return
        }
    }

    private func updateVisibleSelection() {
        guard let overlay, overlay.isOverlayVisible else {
            return
        }

        switch session {
        case let .windows(selection, _):
            overlay.updateWindowSelection(selectedID: selection.selectedItem)
        case let .workspaces(selection, _):
            overlay.updateWorkspaceSelection(selectedID: selection.selectedItem)
        case nil:
            return
        }
    }

    private func moveSelection(_ direction: SwitcherArrowDirection) {
        guard session?.moveWindow(direction) == true else {
            return
        }
        updateVisibleSelection()
    }

    private func commitWorkspace(forShortcutKey key: String) -> Bool {
        guard let selection = session?.workspaceSelection else {
            return false
        }

        let shortcuts = WorkspaceShortcutBindings(controller.currentConfig.bindings)
        guard let workspace = shortcuts.workspace(for: key), selection.items.contains(workspace) else {
            return false
        }

        commitWorkspace(id: workspace)
        return true
    }
}

private extension SwitcherCoordinator {
    private func reconcileActiveSession() {
        let windows = controller.currentWindows()
        switch session {
        case .windows:
            let windowIDs = controller.windows(in: controller.currentWorkspace).map(\.id)
            let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: windowIDs.first)
            guard session?.reconcileWindows(windowIDs, anchorFrame: anchorFrame) == true else {
                endSession()
                return
            }
        case .workspaces:
            let activeWindowID = controller.windows(in: controller.currentWorkspace).first?.id
            let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: activeWindowID)
            guard session?.reconcileWorkspaces(controller.workspaces, anchorFrame: anchorFrame) == true else {
                endSession()
                return
            }
        case nil:
            return
        }

        rebindVisibleSession()
    }

    private func rebindVisibleSession() {
        guard let overlay, overlay.isOverlayVisible else {
            return
        }

        switch session {
        case let .windows(selection, anchorFrame):
            overlay.rebindWindowSwitcher(
                items: previewService.windowItems(ids: selection.items),
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectWindow(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitWindow(id: id)
                }
            )
        case let .workspaces(selection, anchorFrame):
            overlay.rebindWorkspaceSwitcher(
                groups: previewService.workspaceGroups(ids: selection.items),
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectWorkspace(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitWorkspace(id: id)
                }
            )
        case nil:
            return
        }
    }

    private func overlayAnchorFrame(
        from windows: [WindowSnapshot],
        preferredWindowID: WindowID?
    ) -> WindowFrame? {
        if let preferredWindowID,
           let preferredFrame = windows.first(where: { $0.id == preferredWindowID })?.frame {
            return preferredFrame
        }

        return windows.first {
            controller.membership(for: $0.id) == controller.currentWorkspace
                && !controller.isHiddenByWorkspace($0.id)
                && !$0.isMinimized
                && $0.frame != nil
        }?.frame
    }
}

private extension SwitcherCoordinator {
    private func applyPreviewUpdate(_ update: SwitcherPreviewUpdate) {
        guard let overlay, overlay.isOverlayVisible else {
            return
        }

        switch session {
        case let .windows(selection, _):
            let changedIDs = selection.items.filter(update.windowIDs.contains)
            guard !changedIDs.isEmpty else {
                return
            }
            overlay.updateWindowSwitcher(items: previewService.windowItems(ids: changedIDs))
        case let .workspaces(selection, _):
            let changedNames = selection.items.filter(update.workspaceNames.contains)
            guard !changedNames.isEmpty else {
                return
            }
            overlay.updateWorkspaceSwitcher(groups: previewService.workspaceGroups(ids: changedNames))
        case nil:
            return
        }
    }

    private func overlayForPresentation() -> any SwitcherOverlayPresenting {
        if let overlay {
            return overlay
        }

        let overlay = makeOverlay()
        configureInteractions(for: overlay)
        self.overlay = overlay
        return overlay
    }
}
