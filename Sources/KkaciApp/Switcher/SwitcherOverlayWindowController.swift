import AppKit
import KkaciCore

final class SwitcherOverlayWindowController: NSWindowController {
    private let viewFactory = SwitcherOverlayViewFactory()
    private let screenLocator = SwitcherOverlayScreenLocator()
    private var windowListView: WindowSwitcherListView?
    private var workspaceListView: WorkspaceSwitcherListView?

    init() {
        let window = SwitcherOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.isFloatingPanel = true
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.setAccessibilitySubrole(.unknown)
        super.init(window: window)
        window.contentView = viewFactory.rootContentView
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isOverlayVisible: Bool {
        window?.isVisible == true
    }

    func prepare(windowCount: Int, workspaceCount: Int) {
        viewFactory.prepare(windowCount: windowCount, workspaceCount: workspaceCount)
    }

    func showWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    ) {
        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let listView = viewFactory.makeWindowList(
            items: items,
            selectedID: selectedID,
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

    func showWorkspaceSwitcher(
        groups: [WorkspaceSwitcherGroup],
        selectedName: String,
        anchorFrame: WindowFrame?,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) {
        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let listView = viewFactory.makeWorkspaceList(
            groups: groups,
            selectedName: selectedName,
            availableFrame: screenFrame,
            onHover: onHover,
            onClick: onClick
        )
        windowListView = nil
        workspaceListView = listView
        setContent(
            title: nil,
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

    func updateWorkspaceSelection(selectedName: String) {
        workspaceListView?.updateSelection(selectedName: selectedName)
    }

    func hideOverlay() {
        windowListView = nil
        workspaceListView = nil
        window?.alphaValue = 0
        window?.orderOut(nil)
    }

    private func setContent(title: String?, content: NSView) {
        let root = viewFactory.makeRootContent(title: title, content: content)
        let contentSize = root.frame.size
        window?.setContentSize(contentSize)
        root.frame = NSRect(origin: .zero, size: contentSize)
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
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()
    }
}

private final class SwitcherOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }
}
