import AppKit
import CosmosCore

protocol SwitcherOverlayPresenting: AnyObject {
    var isOverlayVisible: Bool { get }

    func setInteractionHandlers(
        onArrowKey: @escaping (SwitcherArrowDirection) -> Void,
        onOutsideClick: @escaping () -> Void,
        onSpaceKey: @escaping (String) -> Bool
    )
    func showWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    )
    func rebindWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    )
    func showSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        anchorFrame: WindowFrame?,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    )
    func rebindSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        anchorFrame: WindowFrame?,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    )
    func updateWindowSwitcher(items: [WindowSwitcherItem])
    func updateWindowSelection(selectedID: WindowID)
    func updateSpaceSwitcher(groups: [SpaceSwitcherGroup])
    func updateSpaceSelection(selectedID: String)
    func hideOverlay()
}

final class SwitcherOverlayWindowController: NSWindowController, SwitcherOverlayPresenting {
    private let contentController: SwitcherOverlayContentController
    private let screenLocator = SwitcherOverlayScreenLocator()
    private var onArrowKey: ((SwitcherArrowDirection) -> Void)?
    private var onOutsideClick: (() -> Void)?
    private var onSpaceKey: ((String) -> Bool)?
    private let outsideClickMonitor = SwitcherOutsideClickMonitor()

    init(appSettingsStore: AppSettingsStore) {
        contentController = SwitcherOverlayContentController(appSettingsStore: appSettingsStore)
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
        window.onArrowKey = { [weak self] direction in
            self?.onArrowKey?(direction)
        }
        window.onSpaceKey = { [weak self] key in
            self?.onSpaceKey?(key) == true
        }
        window.contentView = contentController.rootContentView
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isOverlayVisible: Bool {
        window?.isVisible == true
    }

    func setInteractionHandlers(
        onArrowKey: @escaping (SwitcherArrowDirection) -> Void,
        onOutsideClick: @escaping () -> Void,
        onSpaceKey: @escaping (String) -> Bool
    ) {
        self.onArrowKey = onArrowKey
        self.onOutsideClick = onOutsideClick
        self.onSpaceKey = onSpaceKey
    }

    func showWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    ) {
        contentController.beginWindowPresentation()
        let screenFrame = configureWindowSwitcher(
            items: items,
            selectedID: selectedID,
            anchorFrame: anchorFrame,
            onHover: onHover,
            onClick: onClick
        )
        showOverlay(in: screenFrame)
    }

    func rebindWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    ) {
        guard isOverlayVisible else {
            return
        }
        let screenFrame = configureWindowSwitcher(
            items: items,
            selectedID: selectedID,
            anchorFrame: anchorFrame,
            onHover: onHover,
            onClick: onClick
        )
        positionOverlay(in: screenFrame)
    }

    func showSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        anchorFrame: WindowFrame?,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) {
        contentController.beginSpacePresentation()
        let screenFrame = configureSpaceSwitcher(
            groups: groups,
            selectedID: selectedID,
            anchorFrame: anchorFrame,
            onHover: onHover,
            onClick: onClick
        )
        showOverlay(in: screenFrame)
    }

    func rebindSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        anchorFrame: WindowFrame?,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) {
        guard isOverlayVisible else {
            return
        }
        let screenFrame = configureSpaceSwitcher(
            groups: groups,
            selectedID: selectedID,
            anchorFrame: anchorFrame,
            onHover: onHover,
            onClick: onClick
        )
        positionOverlay(in: screenFrame)
    }

    func updateWindowSwitcher(items: [WindowSwitcherItem]) {
        contentController.updateWindowPreviews(items)
    }

    func updateWindowSelection(selectedID: WindowID) {
        contentController.updateWindowSelection(selectedID)
    }

    func updateSpaceSwitcher(groups: [SpaceSwitcherGroup]) {
        contentController.updateSpacePreviews(groups)
    }

    func updateSpaceSelection(selectedID: String) {
        contentController.updateSpaceSelection(selectedID)
    }

    func hideOverlay() {
        outsideClickMonitor.stop()
        window?.alphaValue = 0
        window?.orderOut(nil)
    }

    private func setContent(_ content: NSView) {
        let root = contentController.configureRootContent(content)
        let contentSize = root.frame.size
        window?.setContentSize(contentSize)
        root.frame = NSRect(origin: .zero, size: contentSize)
    }

    private func configureWindowSwitcher(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        anchorFrame: WindowFrame?,
        onHover: @escaping (WindowID) -> Void,
        onClick: @escaping (WindowID) -> Void
    ) -> NSRect {
        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let listView = contentController.configureWindowList(
            items: items,
            selectedID: selectedID,
            availableFrame: screenFrame,
            onHover: onHover,
            onClick: onClick
        )
        (window as? SwitcherOverlayPanel)?.acceptsSpaceKeys = false
        setContent(listView)
        return screenFrame
    }

    private func configureSpaceSwitcher(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        anchorFrame: WindowFrame?,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) -> NSRect {
        let screenFrame = screenLocator.visibleFrame(for: anchorFrame)
        let listView = contentController.configureSpaceList(
            groups: groups,
            selectedID: selectedID,
            availableFrame: screenFrame,
            onHover: onHover,
            onClick: onClick
        )
        (window as? SwitcherOverlayPanel)?.acceptsSpaceKeys = true
        setContent(listView)
        return screenFrame
    }

    private func showOverlay(in screenFrame: NSRect) {
        guard let window else {
            return
        }

        positionOverlay(in: screenFrame)
        outsideClickMonitor.start(overlayFrame: window.frame) { [weak self] in
            self?.onOutsideClick?()
        }
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()
    }

    private func positionOverlay(in screenFrame: NSRect) {
        guard let window else {
            return
        }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2
        ))
        outsideClickMonitor.updateOverlayFrame(window.frame)
    }
}

private final class SwitcherOverlayPanel: NSPanel {
    var onArrowKey: ((SwitcherArrowDirection) -> Void)?
    var onSpaceKey: ((String) -> Bool)?
    var acceptsSpaceKeys = false

    override var canBecomeKey: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        let direction: SwitcherArrowDirection? = switch event.keyCode {
        case 123: .left
        case 124: .right
        default: nil
        }
        if let direction {
            onArrowKey?(direction)
            return
        }

        if acceptsSpaceKeys,
           let key = KeyboardShortcutKeyCodec.keyName(for: event.keyCode),
           onSpaceKey?(key) == true {
            return
        }
        super.keyDown(with: event)
    }
}
