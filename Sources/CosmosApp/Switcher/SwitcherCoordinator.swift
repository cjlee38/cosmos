import AppKit
import CosmosCore

final class SwitcherCoordinator {
    private let log = Log(category: "switcher")

    private let controller: SpaceController
    private let previewService: SwitcherPreviewService
    private let spaceSwitchCommand: SpaceSwitchCommand
    private let makeOverlay: () -> any SwitcherOverlayPresenting
    private let refreshStatus: () -> Void
    private var overlay: (any SwitcherOverlayPresenting)?
    private var session: ActiveSwitcherSession?
    private var sessionGeneration = 0
    private var pendingOverlayPresentation: DispatchWorkItem?

    init(
        controller: SpaceController,
        previewService: SwitcherPreviewService,
        spaceSwitchCommand: SpaceSwitchCommand,
        refreshStatus: @escaping () -> Void,
        overlay: (any SwitcherOverlayPresenting)? = nil,
        makeOverlay: @escaping () -> any SwitcherOverlayPresenting
    ) {
        self.controller = controller
        self.previewService = previewService
        self.spaceSwitchCommand = spaceSwitchCommand
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
            onSpaceKey: { [weak self] key in
                self?.commitSpace(forShortcutKey: key) == true
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

    func stepSpace(direction: SwitcherDirection) {
        log.trace("step space direction=\(direction)")
        guard session?.stepSpace(direction) == true else {
            startSpaceSession(direction: direction)
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

    func commitSpaceSelection() {
        guard let selection = session?.spaceSelection else {
            return
        }

        commitSpace(id: selection.selectedItem)
    }
}

private extension SwitcherCoordinator {
    private func startWindowSession(direction: SwitcherDirection) {
        let windows = controller.currentWindows()
        let windowIDs = controller.windows(in: controller.currentSpace).map(\.id)

        guard let selection = SwitcherSession(
            items: windowIDs,
            currentItem: windowIDs.first,
            direction: direction
        ) else {
            log.info("No windows in space \(controller.currentSpace)")
            return
        }

        let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: windowIDs.first)
        beginSession(.windows(selection: selection, anchorFrame: anchorFrame))
        log.trace("start windows count=\(selection.items.count) selected=\(selection.selectedIndex)")
    }

    private func startSpaceSession(direction: SwitcherDirection) {
        let windows = controller.currentWindows()
        let activeWindowID = controller.windows(in: controller.currentSpace).first?.id
        let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: activeWindowID)

        guard let selection = SwitcherSession(
            items: controller.spacesByRecency,
            currentItem: controller.currentSpace,
            direction: direction
        ) else {
            log.info("No spaces")
            return
        }

        beginSession(.spaces(selection: selection, anchorFrame: anchorFrame))
        log.trace("start spaces count=\(selection.items.count) selected=\(selection.selectedIndex)")
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

    private func commitSpace(id: String) {
        endSession()

        log.trace("commit space=\(id)")
        do {
            guard try spaceSwitchCommand.execute(to: id) else { return }
            log.info("Switched to space \(id)")
            refreshStatus()
        } catch {
            log.error("Space switch failed: \(String(describing: error))")
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
    private func selectSpace(id: String) -> Bool {
        guard session?.selectSpace(id) == true else {
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
                spaceIDs: [],
                priorityIDs: [selection.selectedItem]
            )
        case let .spaces(selection, anchorFrame):
            overlay.showSpaceSwitcher(
                groups: previewService.spaceGroups(ids: selection.items),
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectSpace(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitSpace(id: id)
                }
            )
            previewService.refresh(
                windowIDs: Set(controller.currentWindows().map(\.id)), spaceIDs: [],
                priorityIDs: controller.windows(in: selection.selectedItem).first.map { [$0.id] } ?? []
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
        case let .spaces(selection, _):
            overlay.updateSpaceSelection(selectedID: selection.selectedItem)
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

    private func commitSpace(forShortcutKey key: String) -> Bool {
        guard let selection = session?.spaceSelection else {
            return false
        }

        let shortcuts = SpaceShortcutBindings(controller.currentConfig.configuredShortcuts)
        guard let spaceID = shortcuts.spaceID(for: key), selection.items.contains(spaceID) else {
            return false
        }

        commitSpace(id: spaceID)
        return true
    }
}

private extension SwitcherCoordinator {
    private func reconcileActiveSession() {
        let windows = controller.currentWindows()
        switch session {
        case .windows:
            let windowIDs = controller.windows(in: controller.currentSpace).map(\.id)
            let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: windowIDs.first)
            guard session?.reconcileWindows(windowIDs, anchorFrame: anchorFrame) == true else {
                endSession()
                return
            }
        case .spaces:
            let activeWindowID = controller.windows(in: controller.currentSpace).first?.id
            let anchorFrame = overlayAnchorFrame(from: windows, preferredWindowID: activeWindowID)
            guard session?.reconcileSpaces(controller.spacesByRecency, anchorFrame: anchorFrame) == true else {
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
        case let .spaces(selection, anchorFrame):
            overlay.rebindSpaceSwitcher(
                groups: previewService.spaceGroups(ids: selection.items),
                selectedID: selection.selectedItem,
                anchorFrame: anchorFrame,
                onHover: { [weak self] id in
                    _ = self?.selectSpace(id: id)
                },
                onClick: { [weak self] id in
                    self?.commitSpace(id: id)
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
            controller.membership(for: $0.id) == controller.currentSpace
                && !controller.isHiddenBySpace($0.id)
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
        case let .spaces(selection, _):
            let changedIDs = selection.items.filter(update.spaceIDs.contains)
            guard !changedIDs.isEmpty else {
                return
            }
            overlay.updateSpaceSwitcher(groups: previewService.spaceGroups(ids: changedIDs))
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
