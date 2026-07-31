import AppKit
import CosmosCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let accessibilityIdentifier = "cosmos.settings"

    private let generalViewController: GeneralSettingsViewController
    private let switcherViewController: SwitcherSettingsViewController
    private let windowViewController: WindowSettingsViewController
    private let spaceViewController: SpaceSettingsViewController
    private let shortcutRecordingController: ShortcutRecordingController
    init(
        generalViewController: GeneralSettingsViewController,
        switcherViewController: SwitcherSettingsViewController,
        windowViewController: WindowSettingsViewController,
        spaceViewController: SpaceSettingsViewController,
        shortcutRecordingController: ShortcutRecordingController
    ) {
        self.generalViewController = generalViewController
        self.switcherViewController = switcherViewController
        self.windowViewController = windowViewController
        self.spaceViewController = spaceViewController
        self.shortcutRecordingController = shortcutRecordingController

        let sidebar = SettingsSidebarViewController()
        let content = SettingsContentViewController()
        let viewControllers: [SettingsSection: NSViewController] = [
            .general: generalViewController,
            .switcher: switcherViewController,
            .window: windowViewController,
            .spaces: spaceViewController
        ]
        sidebar.onSelectionChanged = { section in
            guard shortcutRecordingController.cancel(),
                  let viewController = viewControllers[section]
            else {
                return false
            }
            content.show(viewController)
            return true
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
        panic("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        guard shortcutRecordingController.cancel() else {
            return
        }
        generalViewController.refresh()
        switcherViewController.refresh()
        windowViewController.refresh()
        spaceViewController.refresh()
    }

    func dismiss() -> Bool {
        guard shortcutRecordingController.cancel() else {
            return false
        }
        window?.orderOut(nil)
        return true
    }

    func windowDidBecomeKey(_: Notification) {
        refresh()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard shortcutRecordingController.cancel() else {
            return false
        }
        sender.orderOut(nil)
        return false
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
        sidebarItem.maximumThickness = 180
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
        window.title = "Cosmos Settings"
        window.titleVisibility = .hidden
        configureUnifiedTitlebar(for: window)
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 760, height: 520)
        window.setAccessibilityIdentifier(accessibilityIdentifier)
        window.contentViewController = contentViewController
        return window
    }

    private static func configureUnifiedTitlebar(for window: NSWindow) {
        // The empty toolbar gives AppKit the standard unified sidebar and traffic-light layout.
        let toolbar = NSToolbar(identifier: "cosmos.settings.toolbar")
        toolbar.displayMode = .iconOnly
        toolbar.showsBaselineSeparator = false
        toolbar.allowsUserCustomization = false

        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = toolbar
        window.toolbarStyle = .unified
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
