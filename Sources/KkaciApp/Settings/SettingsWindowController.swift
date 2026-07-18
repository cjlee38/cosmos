import AppKit
import KkaciCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let accessibilityIdentifier = "kkaci.settings"

    private let generalViewController: GeneralSettingsViewController
    private let appearanceViewController: AppearanceSettingsViewController
    private let workspaceViewController: WorkspaceSettingsViewController
    private let visibilityChangedHandler: () -> Void

    init(
        generalSettingsService: GeneralSettingsService,
        appSettingsStore: AppSettingsStore,
        appearanceChangedHandler: @escaping () -> Void,
        visibilityChangedHandler: @escaping () -> Void,
        workspaceSnapshotProvider: @escaping () -> WorkspaceSettingsSnapshot,
        workspaceMonitorChangedHandler: @escaping (String, DisplayID) throws -> Void,
        workspaceAddedHandler: @escaping ([WorkspaceID], DisplayID) throws -> Void,
        workspaceRemovedHandler: @escaping (WorkspaceID) throws -> Void,
        workspaceNameChangedHandler: @escaping (WorkspaceID, String?) throws -> Void,
        shortcutRecordingBeganHandler: @escaping () throws -> Void,
        shortcutRecordingCancelledHandler: @escaping () throws -> Void,
        shortcutChangedHandler: @escaping (ShortcutTarget, String?) throws -> Void,
        configURLProvider: @escaping () -> URL?,
        configStatusProvider: @escaping () -> ConfigRuntimeStatus,
        reloadConfigHandler: @escaping () -> Void
    ) {
        generalViewController = GeneralSettingsViewController(
            service: generalSettingsService,
            configURLProvider: configURLProvider,
            configStatusProvider: configStatusProvider,
            reloadConfigHandler: reloadConfigHandler
        )
        self.visibilityChangedHandler = visibilityChangedHandler
        appearanceViewController = AppearanceSettingsViewController(
            store: appSettingsStore,
            onChange: appearanceChangedHandler
        )
        workspaceViewController = WorkspaceSettingsViewController(
            snapshotProvider: workspaceSnapshotProvider,
            updateMonitorHandler: workspaceMonitorChangedHandler,
            addWorkspaceHandler: workspaceAddedHandler,
            removeWorkspaceHandler: workspaceRemovedHandler,
            updateNameHandler: workspaceNameChangedHandler,
            beginShortcutRecordingHandler: shortcutRecordingBeganHandler,
            cancelShortcutRecordingHandler: shortcutRecordingCancelledHandler,
            updateShortcutHandler: shortcutChangedHandler
        )

        let sidebar = SettingsSidebarViewController()
        let content = SettingsContentViewController()
        let viewControllers: [SettingsSection: NSViewController] = [
            .general: generalViewController,
            .appearance: appearanceViewController,
            .workspaces: workspaceViewController
        ]
        sidebar.onSelectionChanged = { section in
            guard let viewController = viewControllers[section] else {
                return
            }
            content.show(viewController)
        }

        let splitViewController = Self.makeSplitViewController(sidebar: sidebar, content: content)

        let window = Self.makeWindow(contentViewController: splitViewController)

        super.init(window: window)
        window.delegate = self
        content.show(generalViewController)
        sidebar.select(.general)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        refresh()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        visibilityChangedHandler()
    }

    func refresh() {
        generalViewController.refresh()
        appearanceViewController.refresh()
        workspaceViewController.refresh()
    }

    func windowDidBecomeKey(_: Notification) {
        refresh()
    }

    func windowWillClose(_: Notification) {
        workspaceViewController.cancelShortcutRecording()
        NSApp.setActivationPolicy(.accessory)
        visibilityChangedHandler()
    }

    private static func makeSplitViewController(
        sidebar: NSViewController,
        content: NSViewController
    ) -> NSSplitViewController {
        let splitViewController = NSSplitViewController()
        splitViewController.splitView.dividerStyle = .thin
        let sidebarItem = NSSplitViewItem(viewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 220
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: content))
        return splitViewController
    }

    private static func makeWindow(contentViewController: NSViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 790, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "kkaci Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 720, height: 520)
        window.setAccessibilityIdentifier(accessibilityIdentifier)
        window.contentViewController = contentViewController
        return window
    }
}

private final class SettingsContentViewController: NSViewController {
    private var currentViewController: NSViewController?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))
    }

    func show(_ viewController: NSViewController) {
        _ = view
        guard currentViewController !== viewController else {
            return
        }

        if let currentViewController {
            currentViewController.view.removeFromSuperview()
            currentViewController.removeFromParent()
        }

        addChild(viewController)
        let contentView = viewController.view
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        currentViewController = viewController
    }
}

enum SettingsControlFactory {
    static func filledButtonRow(
        actions: [(button: NSButton, action: Selector)],
        target: AnyObject
    ) -> NSStackView {
        for (button, action) in actions {
            button.target = target
            button.action = action
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let buttons = actions.map(\.button)
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    static func actionGroup(details: NSView, actions: NSView) -> NSView {
        let detailsContainer = padded(details)
        let divider = separator()
        let actionsContainer = padded(actions, vertical: 6, horizontal: 6)
        let content = NSStackView(views: [detailsContainer, divider, actionsContainer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        for arrangedView in [detailsContainer, divider, actionsContainer] {
            arrangedView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        return groupBox(content: content)
    }

    static func groupBox(content: NSView) -> NSView {
        SettingsGroupView(content: content)
    }

    static func padded(
        _ content: NSView,
        vertical: CGFloat = 12,
        horizontal: CGFloat = 14
    ) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: vertical),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontal),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontal),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vertical)
        ])
        return container
    }

    static func separator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
}

private final class SettingsGroupView: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
    }
}

final class SettingsFilledButton: NSButton {
    private var isPressed = false

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        font = .systemFont(ofSize: 14, weight: .semibold)
        contentTintColor = .labelColor
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 7
        layer?.opacity = isEnabled ? 1 : 0.45
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateLayer()
        super.mouseDown(with: event)
        isPressed = false
        updateLayer()
    }

    private var backgroundColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(white: isPressed ? 0.27 : 0.20, alpha: 1)
        }
        return NSColor(white: isPressed ? 0.78 : 0.88, alpha: 1)
    }
}
