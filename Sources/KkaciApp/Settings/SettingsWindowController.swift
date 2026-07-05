import AppKit
import KkaciCore

final class SettingsWindowController: NSWindowController {
    private let settingsSnapshotProvider: () -> SettingsSnapshot
    private let reloadConfigHandler: () -> Void
    private let updateWorkspaceMonitorHandler: (String, MonitorSlot) -> Void
    private let renderer = SettingsRenderer()
    private let textView = NSTextView()
    private let monitorSummaryLabel = NSTextField(labelWithString: "")
    private let workspaceMonitorRows = NSStackView()
    private var workspaceByPopupID: [ObjectIdentifier: String] = [:]
    private var isRefreshingControls = false

    init(
        settingsSnapshotProvider: @escaping () -> SettingsSnapshot,
        reloadConfigHandler: @escaping () -> Void,
        updateWorkspaceMonitorHandler: @escaping (String, MonitorSlot) -> Void
    ) {
        self.settingsSnapshotProvider = settingsSnapshotProvider
        self.reloadConfigHandler = reloadConfigHandler
        self.updateWorkspaceMonitorHandler = updateWorkspaceMonitorHandler

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

        let monitorTitle = label("Workspace Monitors")
        monitorTitle.font = .boldSystemFont(ofSize: 13)
        monitorSummaryLabel.lineBreakMode = .byTruncatingTail

        workspaceMonitorRows.translatesAutoresizingMaskIntoConstraints = false
        workspaceMonitorRows.orientation = .vertical
        workspaceMonitorRows.alignment = .leading
        workspaceMonitorRows.spacing = 6

        let monitorSection = NSStackView(views: [monitorTitle, monitorSummaryLabel, workspaceMonitorRows])
        monitorSection.translatesAutoresizingMaskIntoConstraints = false
        monitorSection.orientation = .vertical
        monitorSection.alignment = .leading
        monitorSection.spacing = 8

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

        let root = NSStackView(views: [monitorSection, scrollView, buttons])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            monitorSection.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
        ])
    }

    func refresh() {
        let snapshot = settingsSnapshotProvider()
        textView.string = renderer.render(snapshot)
        rebuildMonitorControls(snapshot)
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func rebuildMonitorControls(_ snapshot: SettingsSnapshot) {
        isRefreshingControls = true
        defer { isRefreshingControls = false }

        workspaceByPopupID.removeAll()
        for view in workspaceMonitorRows.arrangedSubviews {
            workspaceMonitorRows.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let monitors = monitorOptions(from: snapshot)
        monitorSummaryLabel.stringValue = monitors.map(monitorDescription).joined(separator: "   ")

        for workspace in snapshot.runtimeWorkspaces {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8

            let workspaceLabel = label(workspace)
            workspaceLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            workspaceLabel.widthAnchor.constraint(equalToConstant: 80).isActive = true

            let popup = NSPopUpButton()
            popup.translatesAutoresizingMaskIntoConstraints = false
            popup.target = self
            popup.action = #selector(workspaceMonitorChanged(_:))
            popup.widthAnchor.constraint(equalToConstant: 260).isActive = true
            popup.removeAllItems()

            for monitor in monitors {
                let item = NSMenuItem(title: monitorMenuTitle(monitor), action: nil, keyEquivalent: "")
                item.representedObject = monitor.slot
                popup.menu?.addItem(item)
            }

            let selectedSlot = snapshot.monitorSlotsByWorkspace[workspace] ?? snapshot.config.workspaces.monitorSlot(for: workspace)
            if let item = popup.itemArray.first(where: { ($0.representedObject as? MonitorSlot) == selectedSlot }) {
                popup.select(item)
            }

            workspaceByPopupID[ObjectIdentifier(popup)] = workspace
            row.addArrangedSubview(workspaceLabel)
            row.addArrangedSubview(popup)
            workspaceMonitorRows.addArrangedSubview(row)
        }
    }

    private func monitorOptions(from snapshot: SettingsSnapshot) -> [MonitorSlotSnapshot] {
        if !snapshot.monitorSlots.isEmpty {
            return snapshot.monitorSlots
        }

        let slots = Set(snapshot.monitorSlotsByWorkspace.values).sorted()
        return slots.map { slot in
            MonitorSlotSnapshot(
                slot: slot,
                display: DisplaySnapshot(id: UInt32(slot), frame: .zero, isMain: slot == 1)
            )
        }
    }

    private func monitorDescription(_ monitor: MonitorSlotSnapshot) -> String {
        let main = monitor.display.isMain ? " main" : ""
        return "Monitor \(monitor.slot)\(main): usable \(format(monitor.display.visibleFrame.size))"
    }

    private func monitorMenuTitle(_ monitor: MonitorSlotSnapshot) -> String {
        let main = monitor.display.isMain ? " main" : ""
        return "Monitor \(monitor.slot)\(main) - usable \(format(monitor.display.visibleFrame.size))"
    }

    private func format(_ size: CGSize) -> String {
        "\(format(size.width))x\(format(size.height))"
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
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

    @objc private func workspaceMonitorChanged(_ sender: NSPopUpButton) {
        guard !isRefreshingControls,
              let workspace = workspaceByPopupID[ObjectIdentifier(sender)],
              let monitorSlot = sender.selectedItem?.representedObject as? MonitorSlot
        else {
            return
        }

        updateWorkspaceMonitorHandler(workspace, monitorSlot)
        refresh()
    }

    @objc private func closeButtonClicked() {
        close()
    }
}
