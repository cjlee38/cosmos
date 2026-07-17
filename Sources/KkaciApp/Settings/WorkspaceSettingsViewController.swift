import AppKit
import KkaciCore

final class WorkspaceSettingsViewController: NSViewController {
    private let log = Log(category: "settings")
    private let snapshotProvider: () -> WorkspaceSettingsSnapshot
    private let updateMonitorHandler: (String, MonitorSlot) throws -> Void
    private let displayArrangementView = WorkspaceDisplayArrangementView()
    private let displayStatusStack = NSStackView()
    private let keyboardContentStack = NSStackView()

    init(
        snapshotProvider: @escaping () -> WorkspaceSettingsSnapshot,
        updateMonitorHandler: @escaping (String, MonitorSlot) throws -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.updateMonitorHandler = updateMonitorHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        view.addSubview(scrollView)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView

        displayArrangementView.translatesAutoresizingMaskIntoConstraints = false
        displayArrangementView.heightAnchor.constraint(equalToConstant: 190).isActive = true
        configureVerticalStack(displayStatusStack, spacing: 7)
        configureVerticalStack(keyboardContentStack, spacing: 0)

        let displayContent = NSStackView(views: [displayArrangementView, displayStatusStack])
        configureVerticalStack(displayContent, spacing: 8)
        let displaySection = titledSection(
            title: "Displays",
            content: SettingsControlFactory.groupBox(
                content: SettingsControlFactory.padded(displayContent, vertical: 10, horizontal: 10)
            )
        )
        let keyboardSection = titledSection(
            title: "Keyboard",
            content: SettingsControlFactory.groupBox(content: keyboardContentStack)
        )
        let root = NSStackView(views: [makeHeader(), displaySection, keyboardSection])
        configureVerticalStack(root, spacing: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(root)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -26),
            root.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            displaySection.widthAnchor.constraint(equalTo: root.widthAnchor),
            keyboardSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }
        let snapshot = snapshotProvider()
        displayArrangementView.apply(snapshot.displays)
        rebuildDisplayStatus(snapshot)
        rebuildKeyboard(snapshot)
    }
}

private extension WorkspaceSettingsViewController {
    private func makeHeader() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "rectangle.3.group.fill", accessibilityDescription: "Workspaces")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let title = NSTextField(labelWithString: "Workspaces")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let header = NSStackView(views: [icon, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        return header
    }

    private func rebuildDisplayStatus(_ snapshot: WorkspaceSettingsSnapshot) {
        removeArrangedSubviews(from: displayStatusStack)
        let mirroredDisplays = snapshot.displays.filter {
            if case .mirrored = $0.role {
                return true
            }
            return false
        }
        for display in mirroredDisplays {
            let destination = display.mirroredSourceMonitorSlot
                .flatMap { sourceSlot in
                    snapshot.displays.first { $0.monitorSlot == sourceSlot }?.name
                        ?? "Monitor \(sourceSlot)"
                }
                ?? "another display"
            displayStatusStack.addArrangedSubview(statusRow(
                symbol: "rectangle.on.rectangle",
                text: "\(display.name) mirrors \(destination)",
                color: .secondaryLabelColor
            ))
        }
        for monitorSlot in snapshot.disconnectedMonitorSlots {
            let names = snapshot.workspaces
                .filter { $0.monitorSlot == monitorSlot }
                .map(\.name)
                .joined(separator: ", ")
            displayStatusStack.addArrangedSubview(statusRow(
                symbol: "rectangle.slash",
                text: "Monitor \(monitorSlot) · Disconnected    \(names)",
                color: .secondaryLabelColor
            ))
        }

        displayStatusStack.isHidden = displayStatusStack.arrangedSubviews.isEmpty
    }

    private func rebuildKeyboard(_ snapshot: WorkspaceSettingsSnapshot) {
        removeArrangedSubviews(from: keyboardContentStack)
        keyboardContentStack.addArrangedSubview(SettingsControlFactory.padded(
            navigationRow(snapshot.navigation),
            vertical: 10,
            horizontal: 14
        ))
        keyboardContentStack.addArrangedSubview(SettingsControlFactory.separator())
        keyboardContentStack.addArrangedSubview(SettingsControlFactory.padded(
            workspaceGrid(snapshot),
            vertical: 10,
            horizontal: 14
        ))
        for view in keyboardContentStack.arrangedSubviews {
            view.widthAnchor.constraint(equalTo: keyboardContentStack.widthAnchor).isActive = true
        }
    }

    private func navigationRow(_ navigation: WorkspaceNavigationShortcuts) -> NSView {
        let title = valueLabel("Cycle Workspace", weight: .medium)
        let spacer = flexibleSpacer()
        let next = labeledShortcut(title: "Next", shortcut: navigation.next)
        let previous = labeledShortcut(title: "Previous", shortcut: navigation.previous)
        let row = NSStackView(views: [title, spacer, next, previous])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func workspaceGrid(_ snapshot: WorkspaceSettingsSnapshot) -> NSView {
        var rows: [[NSView]] = [[
            headerLabel("Workspace"),
            headerLabel("Display"),
            headerLabel("Switch"),
            headerLabel("Move Window")
        ]]
        rows.append(contentsOf: snapshot.workspaces.map { workspace in
            [
                valueLabel(workspace.name, weight: .semibold),
                monitorSelector(
                    workspace: workspace,
                    connectedDisplays: snapshot.connectedDisplays
                ),
                shortcutBadge(workspace.switchShortcut),
                shortcutBadge(workspace.moveShortcut)
            ]
        })

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).width = 84
        grid.column(at: 1).width = 150
        grid.column(at: 2).width = 104
        grid.column(at: 3).width = 126
        for index in rows.indices {
            grid.row(at: index).yPlacement = .center
        }
        return grid
    }

    private func monitorSelector(
        workspace: WorkspaceSettingsItem,
        connectedDisplays: [WorkspaceSettingsDisplay]
    ) -> NSView {
        let selector = WorkspaceMonitorPopUpButton(
            workspace: workspace.name,
            currentMonitorSlot: workspace.monitorSlot,
            connectedDisplays: connectedDisplays
        )
        selector.target = self
        selector.action = #selector(monitorSelectionChanged(_:))
        return selector
    }

    private func labeledShortcut(title: String, shortcut: String?) -> NSView {
        let label = headerLabel(title)
        let control = shortcutBadge(shortcut)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private func shortcutBadge(_ shortcut: String?) -> NSView {
        ShortcutBadgeView(title: ShortcutDisplayFormatter.format(shortcut), isConfigured: shortcut != nil)
    }

    private func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func valueLabel(_ text: String, weight: NSFont.Weight) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: weight)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func statusRow(symbol: String, text: String, color: NSColor) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = color
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .medium)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    private func titledSection(title: String, content: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let section = NSStackView(views: [titleLabel, content])
        configureVerticalStack(section, spacing: 8)
        content.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func configureVerticalStack(_ stack: NSStackView, spacing: CGFloat) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func removeArrangedSubviews(from stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    @objc private func monitorSelectionChanged(_ sender: WorkspaceMonitorPopUpButton) {
        guard let monitorSlot = sender.selectedItem?.representedObject as? MonitorSlot,
              monitorSlot != sender.currentMonitorSlot
        else {
            return
        }

        do {
            try updateMonitorHandler(sender.workspace, monitorSlot)
        } catch {
            log.error(
                "Workspace monitor update failed workspace=\(sender.workspace) "
                    + "monitor=\(monitorSlot): \(String(describing: error))"
            )
            refresh()
        }
    }
}

private final class WorkspaceMonitorPopUpButton: NSPopUpButton {
    let workspace: String
    let currentMonitorSlot: MonitorSlot

    init(
        workspace: String,
        currentMonitorSlot: MonitorSlot,
        connectedDisplays: [WorkspaceSettingsDisplay]
    ) {
        self.workspace = workspace
        self.currentMonitorSlot = currentMonitorSlot
        super.init(frame: .zero, pullsDown: false)

        setAccessibilityIdentifier("kkaci.settings.workspace.\(workspace).monitor")
        controlSize = .small
        font = .systemFont(ofSize: 12, weight: .medium)
        let labelsByMonitorSlot = Dictionary(uniqueKeysWithValues: connectedDisplays.compactMap { display in
            display.monitorSlot.map { monitorSlot in
                (monitorSlot, display.name)
            }
        })
        let availableSlots = Set(labelsByMonitorSlot.keys)
        let options = availableSlots.union([currentMonitorSlot]).sorted()
        for monitorSlot in options {
            let isConnected = availableSlots.contains(monitorSlot)
            let title = labelsByMonitorSlot[monitorSlot] ?? "Monitor \(monitorSlot)"
            addItem(withTitle: title)
            let item = itemArray[itemArray.count - 1]
            item.representedObject = monitorSlot
            item.isEnabled = isConnected
            if !isConnected {
                item.title += " · Disconnected"
            }
            if monitorSlot == currentMonitorSlot {
                select(item)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ShortcutBadgeView: NSView {
    init(title: String, isConfigured: Bool) {
        super.init(frame: .zero)
        wantsLayer = true

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = isConfigured ? .labelColor : .tertiaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
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
        layer?.cornerRadius = 6
    }
}
