import AppKit
import KkaciCore

final class WorkspaceSettingsViewController: NSViewController {
    private let log = Log(category: "settings")
    private let snapshotProvider: () -> WorkspaceSettingsSnapshot
    private let updateMonitorHandler: (String, MonitorSlot) throws -> Void
    private let addWorkspaceHandler: (WorkspaceID) throws -> Void
    private let removeWorkspaceHandler: (WorkspaceID) throws -> Void
    private let displayArrangementView = WorkspaceDisplayArrangementView()
    private let displayStatusStack = NSStackView()
    private let keyboardContentStack = NSStackView()

    init(
        snapshotProvider: @escaping () -> WorkspaceSettingsSnapshot,
        updateMonitorHandler: @escaping (String, MonitorSlot) throws -> Void,
        addWorkspaceHandler: @escaping (WorkspaceID) throws -> Void,
        removeWorkspaceHandler: @escaping (WorkspaceID) throws -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.updateMonitorHandler = updateMonitorHandler
        self.addWorkspaceHandler = addWorkspaceHandler
        self.removeWorkspaceHandler = removeWorkspaceHandler
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
                .map(\.id.rawValue)
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
            headerLabel("Move Window"),
            addWorkspaceButton(snapshot.availableWorkspaceIDs)
        ]]
        rows.append(contentsOf: snapshot.workspaces.map { workspace in
            [
                valueLabel(workspace.id.rawValue, weight: .semibold),
                monitorSelector(
                    workspace: workspace,
                    connectedDisplays: snapshot.connectedDisplays
                ),
                shortcutBadge(workspace.switchShortcut),
                shortcutBadge(workspace.moveShortcut),
                removeWorkspaceButton(workspace.id, isEnabled: snapshot.workspaces.count > 1)
            ]
        })

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).width = 84
        grid.column(at: 1).width = 150
        grid.column(at: 2).width = 104
        grid.column(at: 3).width = 126
        grid.column(at: 4).width = 28
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
            workspaceID: workspace.id,
            currentMonitorSlot: workspace.monitorSlot,
            connectedDisplays: connectedDisplays
        )
        selector.target = self
        selector.action = #selector(monitorSelectionChanged(_:))
        return selector
    }

    private func addWorkspaceButton(_ availableWorkspaceIDs: [WorkspaceID]) -> NSButton {
        let button = WorkspaceAddButton(availableWorkspaceIDs: availableWorkspaceIDs)
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Workspace")
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.toolTip = "Add Workspace"
        button.target = self
        button.action = #selector(showAddWorkspaceMenu(_:))
        button.isEnabled = !availableWorkspaceIDs.isEmpty
        button.setAccessibilityIdentifier("kkaci.settings.workspace.add")
        return button
    }

    private func removeWorkspaceButton(_ workspaceID: WorkspaceID, isEnabled: Bool) -> NSButton {
        let button = WorkspaceRemoveButton(workspaceID: workspaceID)
        button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Workspace")
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.toolTip = isEnabled ? "Delete Workspace \(workspaceID.rawValue)" : "At least one workspace is required"
        button.target = self
        button.action = #selector(removeWorkspace(_:))
        button.isEnabled = isEnabled
        button.setAccessibilityIdentifier("kkaci.settings.workspace.\(workspaceID.rawValue).remove")
        return button
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
            try updateMonitorHandler(sender.workspaceID.rawValue, monitorSlot)
        } catch {
            log.error(
                "Workspace monitor update failed workspace=\(sender.workspaceID.rawValue) "
                    + "monitor=\(monitorSlot): \(String(describing: error))"
            )
            refresh()
        }
    }

    @objc private func showAddWorkspaceMenu(_ sender: WorkspaceAddButton) {
        let menu = WorkspaceAddMenu(
            workspaceIDs: sender.availableWorkspaceIDs,
            target: self,
            action: #selector(addWorkspace(_:))
        )
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc private func addWorkspace(_ sender: WorkspaceIDMenuItem) {
        do {
            try addWorkspaceHandler(sender.workspaceID)
        } catch {
            log.error("Workspace add failed id=\(sender.workspaceID.rawValue): \(String(describing: error))")
            refresh()
        }
    }

    @objc private func removeWorkspace(_ sender: WorkspaceRemoveButton) {
        let alert = NSAlert()
        alert.messageText = "Delete Workspace \(sender.workspaceID.rawValue)?"
        alert.informativeText = "Its windows will move to the current workspace."
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Workspace")
        alert.addButton(withTitle: "Delete")
        alert.buttons[0].hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        do {
            try removeWorkspaceHandler(sender.workspaceID)
        } catch {
            log.error("Workspace removal failed id=\(sender.workspaceID.rawValue): \(String(describing: error))")
            refresh()
        }
    }
}
