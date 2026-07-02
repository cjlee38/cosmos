import AppKit

final class SettingsWindowController: NSWindowController {
    private let settingsSnapshotProvider: () -> SettingsSnapshot
    private let reloadConfigHandler: () -> Void
    private let textView = NSTextView()

    init(
        settingsSnapshotProvider: @escaping () -> SettingsSnapshot,
        reloadConfigHandler: @escaping () -> Void
    ) {
        self.settingsSnapshotProvider = settingsSnapshotProvider
        self.reloadConfigHandler = reloadConfigHandler

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "kkaci Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let contentView = window?.contentView else {
            return
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.frame = NSRect(x: 0, y: 0, width: 680, height: 420)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.documentView = textView

        let openButton = button("Open Config", action: #selector(openConfig))
        let revealButton = button("Reveal in Finder", action: #selector(revealConfig))
        let reloadButton = button("Reload Config", action: #selector(reloadConfig))
        let refreshButton = button("Refresh", action: #selector(refreshButtonClicked))
        let closeButton = button("Close", action: #selector(closeButtonClicked))

        let buttons = NSStackView(views: [openButton, revealButton, reloadButton, refreshButton, closeButton])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        contentView.addSubview(scrollView)
        contentView.addSubview(buttons)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),

            buttons.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    func refresh() {
        textView.string = renderSettings()
    }

    private func renderSettings() -> String {
        let snapshot = settingsSnapshotProvider()
        let config = snapshot.config
        var lines: [String] = [
            "kkaci settings",
            "config: \(snapshot.configURL?.path ?? "(not file-backed)")",
            "active workspace: \(snapshot.activeWorkspace)",
            "",
            "runtime workspaces:",
        ]

        for workspace in snapshot.runtimeWorkspaces {
            let marker = workspace == snapshot.activeWorkspace ? "*" : " "
            lines.append("  \(marker) \(workspace)")
        }

        lines.append("")
        lines.append("config workspaces:")
        for workspace in config.workspaces.names {
            lines.append("  - \(workspace)")
        }

        lines.append("")
        lines.append("hotkeys:")
        if config.bindings.isEmpty {
            lines.append("  (none)")
        } else {
            for binding in config.bindings {
                var line = "  \(binding.key) -> \(binding.command)"
                if let workspace = binding.workspace {
                    line += " \(workspace)"
                }
                lines.append(line)
            }
        }

        return lines.joined(separator: "\n")
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func openConfig() {
        guard let url = settingsSnapshotProvider().configURL else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealConfig() {
        guard let url = settingsSnapshotProvider().configURL else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func reloadConfig() {
        reloadConfigHandler()
        refresh()
    }

    @objc private func refreshButtonClicked() {
        refresh()
    }

    @objc private func closeButtonClicked() {
        close()
    }
}
