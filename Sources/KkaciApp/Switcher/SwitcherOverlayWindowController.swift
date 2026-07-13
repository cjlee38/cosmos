import AppKit
import KkaciCore

final class SwitcherOverlayWindowController: NSWindowController {
    private let viewFactory = SwitcherOverlayViewFactory()
    private let screenLocator = SwitcherOverlayScreenLocator()
    private var windowListView: WindowSwitcherListView?
    private var workspaceListView: WorkspaceSwitcherListView?
    private var onArrowKey: ((SwitcherArrowDirection) -> Void)?
    private var onOutsideClick: (() -> Void)?
    private var onWorkspaceKey: ((String) -> Bool)?
    private let outsideClickMonitor = SwitcherOutsideClickMonitor()

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
        window.onArrowKey = { [weak self] direction in
            self?.onArrowKey?(direction)
        }
        window.onWorkspaceKey = { [weak self] key in
            self?.onWorkspaceKey?(key) == true
        }
        window.contentView = viewFactory.rootContentView
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
        onWorkspaceKey: @escaping (String) -> Bool
    ) {
        self.onArrowKey = onArrowKey
        self.onOutsideClick = onOutsideClick
        self.onWorkspaceKey = onWorkspaceKey
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
        (window as? SwitcherOverlayPanel)?.acceptsWorkspaceKeys = false
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
        (window as? SwitcherOverlayPanel)?.acceptsWorkspaceKeys = true
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
        outsideClickMonitor.stop()
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
        outsideClickMonitor.start(overlayFrame: window.frame) { [weak self] in
            self?.onOutsideClick?()
        }
        window.alphaValue = 1
        window.orderFrontRegardless()
        window.makeKey()
    }
}

private final class SwitcherOverlayPanel: NSPanel {
    var onArrowKey: ((SwitcherArrowDirection) -> Void)?
    var onWorkspaceKey: ((String) -> Bool)?
    var acceptsWorkspaceKeys = false

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

        if acceptsWorkspaceKeys,
           let key = event.charactersIgnoringModifiers?.lowercased(),
           onWorkspaceKey?(key) == true {
            return
        }
        super.keyDown(with: event)
    }
}

private final class SwitcherOutsideClickMonitor {
    private let log = Log(category: "switcher")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayFrame = NSRect.zero
    private var onOutsideClick: (() -> Void)?
    private var isActive = false

    deinit {
        invalidate()
    }

    func start(overlayFrame: NSRect, onOutsideClick: @escaping () -> Void) {
        self.overlayFrame = overlayFrame
        self.onOutsideClick = onOutsideClick
        isActive = true

        if eventTap == nil {
            createEventTap()
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func stop() {
        isActive = false
        onOutsideClick = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard isActive, !overlayFrame.contains(NSEvent.mouseLocation) else {
                return Unmanaged.passUnretained(event)
            }

            isActive = false
            DispatchQueue.main.async { [weak self] in
                self?.onOutsideClick?()
            }
            return nil
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isActive, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func createEventTap() {
        let mouseDownMask = [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ].reduce(CGEventMask(0)) { mask, type in
            mask | CGEventMask(1 << type.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mouseDownMask,
            callback: switcherOutsideClickEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            log.error("Failed to create outside-click event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private func invalidate() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }
}

private func switcherOutsideClickEventTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    return Unmanaged<SwitcherOutsideClickMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}
