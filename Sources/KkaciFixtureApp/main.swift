import AppKit

final class FixtureAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let secureInputControl = SecureInputFixtureControl()
    private var controlWindow: NSWindow?
    private var fixtureWindows: [NSWindow] = []
    private weak var activeModalWindow: NSWindow?
    private var sequence = 1

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        showControlWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        if controlWindow?.isVisible != true {
            showControlWindow()
        }
        return true
    }

    func applicationWillTerminate(_: Notification) {
        secureInputControl.disable()
    }
}

private extension FixtureAppDelegate {
    private func showControlWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 480, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "kkaci Fixture Control"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 420)
        window.contentView = buildControlView()
        window.center()
        window.makeKeyAndOrderFront(nil)
        controlWindow = window
    }

    private func buildControlView() -> NSView {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "kkaci fixture windows")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let descriptionText = "Open external AppKit windows with known titles and behaviors "
            + "for kkaci AX/manual verification."
        let description = NSTextField(wrappingLabelWithString: descriptionText)
        description.textColor = .secondaryLabelColor

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(description)
        stack.setCustomSpacing(18, after: description)
        stack.addArrangedSubview(secureInputControl.makeView())

        for spec in buttonSpecs() {
            let button = NSButton(title: spec.title, target: self, action: spec.action)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.bezelStyle = .rounded
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
            stack.addArrangedSubview(button)
        }

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -22)
        ])

        return root
    }

    private func buttonSpecs() -> [(title: String, action: Selector)] {
        [
            ("Open Normal Window", #selector(openNormalWindow)),
            ("Open Second Normal Window", #selector(openSecondNormalWindow)),
            ("Open Fixed-Size Window", #selector(openFixedSizeWindow)),
            ("Open Utility Panel", #selector(openUtilityPanel)),
            ("Open Floating Panel", #selector(openFloatingPanel)),
            ("Open Untitled Window", #selector(openUntitledWindow)),
            ("Open Minimized Window", #selector(openMinimizedWindow)),
            ("Open Sheet", #selector(openSheet)),
            ("Open Modal Dialog", #selector(openModalDialog)),
            ("Close Fixture Windows", #selector(closeFixtureWindows))
        ]
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "Quit kkaci Fixture App",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func openNormalWindow() {
        makeFixtureWindow(title: nextTitle("Normal"), size: NSSize(width: 520, height: 360))
    }

    @objc private func openSecondNormalWindow() {
        makeFixtureWindow(title: nextTitle("Normal Secondary"), size: NSSize(width: 540, height: 360))
    }

    @objc private func openFixedSizeWindow() {
        let window = makeFixtureWindow(
            title: nextTitle("Fixed Size"),
            size: NSSize(width: 420, height: 260),
            styleMask: [.titled, .closable, .miniaturizable]
        )
        window.minSize = window.frame.size
        window.maxSize = window.frame.size
    }

    @objc private func openUtilityPanel() {
        let panel = makePanel(
            title: nextTitle("Utility Panel"),
            size: NSSize(width: 420, height: 260),
            styleMask: [.titled, .closable, .utilityWindow]
        )
        panel.becomesKeyOnlyIfNeeded = false
        showFixtureWindow(panel)
    }

    @objc private func openFloatingPanel() {
        let panel = makePanel(
            title: nextTitle("Floating Panel"),
            size: NSSize(width: 420, height: 260),
            styleMask: [.titled, .closable, .resizable, .utilityWindow]
        )
        panel.level = .floating
        showFixtureWindow(panel)
    }

    @objc private func openUntitledWindow() {
        makeFixtureWindow(title: "", size: NSSize(width: 440, height: 300))
    }

    @objc private func openMinimizedWindow() {
        let window = makeFixtureWindow(title: nextTitle("Minimized"), size: NSSize(width: 480, height: 320))
        window.miniaturize(nil)
    }

    @objc private func openSheet() {
        let parent = makeFixtureWindow(title: nextTitle("Sheet Parent"), size: NSSize(width: 520, height: 340))
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        sheet.title = "KKACI Fixture Sheet"
        sheet.isReleasedWhenClosed = false
        sheet.contentView = makeContentView(title: "Sheet", subtitle: "Attached sheet window")
        parent.beginSheet(sheet)
    }

    @objc private func openModalDialog() {
        let dialog = NSWindow(
            contentRect: NSRect(origin: nextOrigin(), size: NSSize(width: 380, height: 220)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        dialog.title = nextTitle("Modal Dialog")
        dialog.isReleasedWhenClosed = false
        dialog.delegate = self
        dialog.contentView = makeDialogContentView(title: dialog.title)
        fixtureWindows.append(dialog)
        activeModalWindow = dialog
        dialog.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: dialog)
    }

    @objc private func closeModalDialog() {
        guard let activeModalWindow else {
            return
        }
        NSApp.stopModal()
        activeModalWindow.close()
        self.activeModalWindow = nil
    }

    @objc private func closeFixtureWindows() {
        for window in fixtureWindows {
            if let sheet = window.attachedSheet {
                window.endSheet(sheet)
            }
            window.close()
        }
        fixtureWindows.removeAll()
    }
}

extension FixtureAppDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === activeModalWindow
        else {
            return
        }
        NSApp.stopModal()
        activeModalWindow = nil
    }
}

private extension FixtureAppDelegate {
    @discardableResult
    private func makeFixtureWindow(
        title: String,
        size: NSSize,
        styleMask: NSWindow.StyleMask = [.titled, .closable, .resizable, .miniaturizable],
        activate: Bool = true
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: nextOrigin(), size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView(
            title: title.isEmpty ? "(untitled)" : title,
            subtitle: "pid \(getpid())"
        )
        showFixtureWindow(window, activate: activate)
        return window
    }

    private func makePanel(title: String, size: NSSize, styleMask: NSWindow.StyleMask) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: nextOrigin(), size: size),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.contentView = makeContentView(title: title, subtitle: "NSPanel fixture")
        return panel
    }

    private func showFixtureWindow(_ window: NSWindow, activate: Bool = true) {
        fixtureWindows.append(window)
        window.makeKeyAndOrderFront(nil)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func makeContentView(title: String, subtitle: String) -> NSView {
        let root = NSView()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(titleLabel)
        root.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28)
        ])

        return root
    }

    private func makeDialogContentView(title: String) -> NSView {
        let root = NSView()

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let subtitleLabel = NSTextField(labelWithString: "Application-modal dialog fixture")
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = NSButton(title: "Close Dialog", target: self, action: #selector(closeModalDialog))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .rounded

        root.addSubview(titleLabel)
        root.addSubview(subtitleLabel)
        root.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -28),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            closeButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])

        return root
    }

    private func nextTitle(_ kind: String) -> String {
        defer { sequence += 1 }
        return "KKACI Fixture \(kind) \(sequence)"
    }

    private func nextOrigin() -> NSPoint {
        let offset = CGFloat((sequence % 8) * 34)
        return NSPoint(x: 180 + offset, y: 180 + offset)
    }
}

let app = NSApplication.shared
let delegate = FixtureAppDelegate()
app.delegate = delegate
app.run()
