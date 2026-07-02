import AppKit
import KkaciCore

final class SwitcherOverlayWindowController: NSWindowController {
    private let viewFactory = SwitcherOverlayViewFactory()
    private let screenLocator = SwitcherOverlayScreenLocator()
    private var windowListView: WindowSwitcherListView?
    private var workspaceListView: WorkspaceSwitcherListView?

    init() {
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 460),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowSwitcher(items: [WindowSwitcherItem], selectedIndex: Int, anchorFrame: WindowFrame?) {
        let listView = viewFactory.makeWindowList(items: items, selectedIndex: selectedIndex, compact: false)
        windowListView = listView
        workspaceListView = nil
        setContent(
            title: "Windows",
            content: listView
        )
        showOverlay(anchorFrame: anchorFrame)
    }

    func showWorkspaceSwitcher(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?) {
        let listView = viewFactory.makeWorkspaceList(groups: groups, selectedIndex: selectedIndex)
        windowListView = nil
        workspaceListView = listView
        setContent(
            title: "Workspaces",
            content: listView
        )
        showOverlay(anchorFrame: anchorFrame)
    }

    func updateWindowSwitcher(items: [WindowSwitcherItem]) {
        windowListView?.updatePreviews(items: items)
    }

    func updateWorkspaceSwitcher(groups: [WorkspaceSwitcherGroup]) {
        workspaceListView?.updatePreviews(groups: groups)
    }

    func hideOverlay() {
        windowListView = nil
        workspaceListView = nil
        window?.orderOut(nil)
    }

    private func setContent(title: String, content: NSView) {
        window?.contentView = viewFactory.makeRootContent(title: title, content: content)
    }

    private func showOverlay(anchorFrame: WindowFrame?) {
        guard let window else {
            return
        }

        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        ))
        window.orderFrontRegardless()
    }
}
