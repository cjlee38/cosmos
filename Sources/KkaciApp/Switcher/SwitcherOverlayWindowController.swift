import AppKit
import KkaciCore

final class SwitcherOverlayWindowController: NSWindowController {
    private let viewFactory = SwitcherOverlayViewFactory()
    private let screenLocator = SwitcherOverlayScreenLocator()
    private var windowListView: WindowSwitcherListView?
    private var workspaceListView: WorkspaceSwitcherListView?

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedIndex: Int,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    ) {
        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let listView = viewFactory.makeWindowList(
            items: items,
            selectedIndex: selectedIndex,
            compact: false,
            availableFrame: screenFrame,
            onHover: onHover,
            onClick: onClick
        )
        windowListView = listView
        workspaceListView = nil
        setContent(
            title: nil,
            content: listView
        )
        showOverlay(in: screenFrame)
    }

    func showWorkspaceSwitcher(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?) {
        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let listView = viewFactory.makeWorkspaceList(
            groups: groups,
            selectedIndex: selectedIndex,
            availableFrame: screenFrame
        )
        windowListView = nil
        workspaceListView = listView
        setContent(
            title: "Workspaces",
            content: listView
        )
        showOverlay(in: screenFrame)
    }

    func updateWindowSwitcher(items: [WindowSwitcherItem]) {
        windowListView?.updatePreviews(items: items)
    }

    func updateWindowSelection(selectedID: WindowID) {
        windowListView?.updateSelection(selectedID: selectedID)
    }

    func updateWorkspaceSwitcher(groups: [WorkspaceSwitcherGroup]) {
        workspaceListView?.updatePreviews(groups: groups)
    }

    func hideOverlay() {
        windowListView = nil
        workspaceListView = nil
        window?.orderOut(nil)
    }

    private func setContent(title: String?, content: NSView) {
        let root = viewFactory.makeRootContent(title: title, content: content)
        let contentSize = root.frame.size
        window?.setContentSize(contentSize)
        root.frame = NSRect(origin: .zero, size: contentSize)
        window?.contentView = root
    }

    private func showOverlay(in screenFrame: NSRect) {
        guard let window else {
            return
        }

        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        ))
        window.orderFrontRegardless()
    }
}
