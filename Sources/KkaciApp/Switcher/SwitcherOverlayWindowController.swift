import AppKit
import KkaciCore

final class SwitcherOverlayWindowController: NSWindowController {
    private let viewFactory = SwitcherOverlayViewFactory()
    private let screenLocator = SwitcherOverlayScreenLocator()

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
        setContent(
            title: "Windows",
            content: viewFactory.makeWindowList(items: items, selectedIndex: selectedIndex, compact: false)
        )
        showOverlay(anchorFrame: anchorFrame)
    }

    func showWorkspaceSwitcher(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, anchorFrame: WindowFrame?) {
        setContent(
            title: "Workspaces",
            content: viewFactory.makeWorkspaceList(groups: groups, selectedIndex: selectedIndex)
        )
        showOverlay(anchorFrame: anchorFrame)
    }

    func hideOverlay() {
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
