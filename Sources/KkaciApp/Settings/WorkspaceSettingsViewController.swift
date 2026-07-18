import AppKit
import KkaciCore

final class WorkspaceSettingsViewController: NSViewController, NSTextFieldDelegate {
    private let log = Log(category: "settings")
    private let snapshotProvider: () -> WorkspaceSettingsSnapshot
    private let updateMonitorHandler: (String, DisplayID) throws -> Void
    private let addWorkspaceHandler: ([WorkspaceID], DisplayID) throws -> Void
    private let removeWorkspaceHandler: (WorkspaceID) throws -> Void
    private let updateNameHandler: (WorkspaceID, String?) throws -> Void
    private let beginShortcutRecordingHandler: () throws -> Void
    private let cancelShortcutRecordingHandler: () throws -> Void
    private let updateShortcutHandler: (ShortcutTarget, String?) throws -> Void
    private let displayArrangementView = WorkspaceDisplayArrangementView()
    private let displayStatusStack = NSStackView()
    private let keyboardContentStack = NSStackView()
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var configErrorNotice = WorkspaceSettingsControlFactory.configErrorNotice(label: configErrorLabel)
    private weak var activeShortcutRecorder: ShortcutRecorderButton?

    init(
        snapshotProvider: @escaping () -> WorkspaceSettingsSnapshot,
        updateMonitorHandler: @escaping (String, DisplayID) throws -> Void,
        addWorkspaceHandler: @escaping ([WorkspaceID], DisplayID) throws -> Void,
        removeWorkspaceHandler: @escaping (WorkspaceID) throws -> Void,
        updateNameHandler: @escaping (WorkspaceID, String?) throws -> Void,
        beginShortcutRecordingHandler: @escaping () throws -> Void,
        cancelShortcutRecordingHandler: @escaping () throws -> Void,
        updateShortcutHandler: @escaping (ShortcutTarget, String?) throws -> Void
    ) {
        self.snapshotProvider = snapshotProvider
        self.updateMonitorHandler = updateMonitorHandler
        self.addWorkspaceHandler = addWorkspaceHandler
        self.removeWorkspaceHandler = removeWorkspaceHandler
        self.updateNameHandler = updateNameHandler
        self.beginShortcutRecordingHandler = beginShortcutRecordingHandler
        self.cancelShortcutRecordingHandler = cancelShortcutRecordingHandler
        self.updateShortcutHandler = updateShortcutHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))

        let (scrollView, documentView) = makeScrollView()
        view.addSubview(scrollView)

        displayArrangementView.translatesAutoresizingMaskIntoConstraints = false
        displayArrangementView.heightAnchor.constraint(equalToConstant: 190).isActive = true
        configureVerticalStack(displayStatusStack, spacing: 7)
        configureVerticalStack(keyboardContentStack, spacing: 0)

        let displayContent = NSStackView(views: [displayArrangementView, displayStatusStack])
        configureVerticalStack(displayContent, spacing: 8)
        let displaySection = WorkspaceSettingsControlFactory.titledSection(
            title: "Displays",
            content: SettingsControlFactory.groupBox(
                content: SettingsControlFactory.padded(displayContent, vertical: 10, horizontal: 10)
            )
        )
        let keyboardSection = WorkspaceSettingsControlFactory.titledSection(
            title: "Keyboard",
            content: SettingsControlFactory.groupBox(content: keyboardContentStack)
        )
        let root = NSStackView(views: [
            WorkspaceSettingsControlFactory.header(),
            displaySection,
            configErrorNotice,
            keyboardSection
        ])
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
            configErrorNotice.widthAnchor.constraint(equalTo: root.widthAnchor),
            keyboardSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }
        cancelShortcutRecording()
        let snapshot = snapshotProvider()
        displayArrangementView.apply(snapshot.displays)
        rebuildDisplayStatus(snapshot)
        rebuildKeyboard(snapshot)
        updateEditingState(snapshot)
    }

    func cancelShortcutRecording() {
        activeShortcutRecorder?.cancelRecording()
    }

    override func viewWillDisappear() {
        cancelShortcutRecording()
        super.viewWillDisappear()
    }
}

private extension WorkspaceSettingsViewController {
    private func makeScrollView() -> (scrollView: NSScrollView, documentView: NSView) {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        return (scrollView, documentView)
    }

    private func rebuildDisplayStatus(_ snapshot: WorkspaceSettingsSnapshot) {
        removeArrangedSubviews(from: displayStatusStack)
        for monitorSlot in snapshot.disconnectedMonitorSlots {
            let names = snapshot.workspaces
                .filter { $0.monitorSlot == monitorSlot }
                .map(\.id.rawValue)
                .joined(separator: ", ")
            displayStatusStack.addArrangedSubview(WorkspaceSettingsControlFactory.statusRow(
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
            WorkspaceSettingsControlFactory.switcherRow(
                title: "Cycle Workspace",
                shortcuts: snapshot.workspaceSwitcher,
                targets: (.workspaceSwitcherNext, .workspaceSwitcherPrevious),
                validationMessages: snapshot.shortcutValidationMessages,
                action: (self, #selector(beginShortcutRecording(_:)))
            ),
            vertical: 10,
            horizontal: 14
        ))
        keyboardContentStack.addArrangedSubview(SettingsControlFactory.separator())
        keyboardContentStack.addArrangedSubview(SettingsControlFactory.padded(
            WorkspaceSettingsControlFactory.switcherRow(
                title: "Cycle Window",
                shortcuts: snapshot.windowSwitcher,
                targets: (.windowSwitcherNext, .windowSwitcherPrevious),
                validationMessages: snapshot.shortcutValidationMessages,
                action: (self, #selector(beginShortcutRecording(_:)))
            ),
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

    private func workspaceGrid(_ snapshot: WorkspaceSettingsSnapshot) -> NSView {
        var rows: [[NSView]] = [[
            WorkspaceSettingsControlFactory.headerLabel("Workspace"),
            WorkspaceSettingsControlFactory.headerLabel("Display"),
            WorkspaceSettingsControlFactory.headerLabel("Switch"),
            WorkspaceSettingsControlFactory.headerLabel("Move Window"),
            WorkspaceSettingsControlFactory.addButton(
                availableWorkspaceIDs: snapshot.availableWorkspaceIDs,
                target: self,
                action: #selector(showAddWorkspacePicker(_:))
            )
        ]]
        rows.append(contentsOf: snapshot.workspaces.map { workspaceRow($0, snapshot: snapshot) })

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).width = 134
        grid.column(at: 1).width = 126
        grid.column(at: 2).width = 94
        grid.column(at: 3).width = 112
        grid.column(at: 4).width = 28
        for index in rows.indices {
            grid.row(at: index).yPlacement = .center
        }
        return grid
    }

    private func workspaceRow(
        _ workspace: WorkspaceSettingsItem,
        snapshot: WorkspaceSettingsSnapshot
    ) -> [NSView] {
        [
            WorkspaceSettingsControlFactory.identityEditor(workspace: workspace, delegate: self),
            monitorSelector(workspace: workspace, displays: snapshot.displays),
            WorkspaceSettingsControlFactory.shortcutRecorder(
                shortcutTarget: .switchWorkspace(workspace.id),
                shortcut: workspace.switchShortcut,
                validationMessage: snapshot.shortcutValidationMessage(for: .switchWorkspace(workspace.id)),
                target: self,
                action: #selector(beginShortcutRecording(_:))
            ),
            WorkspaceSettingsControlFactory.shortcutRecorder(
                shortcutTarget: .moveWindow(workspace.id),
                shortcut: workspace.moveShortcut,
                validationMessage: snapshot.shortcutValidationMessage(for: .moveWindow(workspace.id)),
                target: self,
                action: #selector(beginShortcutRecording(_:))
            ),
            WorkspaceSettingsControlFactory.removeButton(
                workspaceID: workspace.id,
                isEnabled: snapshot.workspaces.count > 1,
                target: self,
                action: #selector(removeWorkspace(_:))
            )
        ]
    }

    private func monitorSelector(
        workspace: WorkspaceSettingsItem,
        displays: [WorkspaceSettingsDisplay]
    ) -> NSView {
        let selector = WorkspaceMonitorPopUpButton(
            workspaceID: workspace.id,
            currentMonitorSlot: workspace.monitorSlot,
            displays: displays
        )
        selector.target = self
        selector.action = #selector(monitorSelectionChanged(_:))
        return selector
    }

    private func configureVerticalStack(_ stack: NSStackView, spacing: CGFloat) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
    }

    private func removeArrangedSubviews(from stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func updateEditingState(_ snapshot: WorkspaceSettingsSnapshot) {
        configErrorLabel.stringValue = snapshot.isEditable
            ? ""
            : "Configuration is invalid. Fix config.yaml in General before editing workspaces."
        configErrorNotice.isHidden = snapshot.isEditable
        if !snapshot.isEditable {
            disableControls(in: keyboardContentStack)
        }
    }

    private func disableControls(in view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = false
        }
        for subview in view.subviews {
            disableControls(in: subview)
        }
    }

    @objc private func monitorSelectionChanged(_ sender: WorkspaceMonitorPopUpButton) {
        guard let displayID = sender.selectedItem?.representedObject as? DisplayID,
              displayID != sender.currentDisplayID
        else {
            return
        }

        do {
            try updateMonitorHandler(sender.workspaceID.rawValue, displayID)
        } catch {
            log.error(
                "Workspace monitor update failed workspace=\(sender.workspaceID.rawValue) "
                    + "display=\(displayID): \(String(describing: error))"
            )
            refresh()
        }
    }

    @objc private func beginShortcutRecording(_ sender: ShortcutRecorderButton) {
        activeShortcutRecorder?.cancelRecording()
        do {
            try beginShortcutRecordingHandler()
        } catch {
            log.error("Shortcut recording failed to start: \(String(describing: error))")
            NSSound.beep()
            return
        }

        activeShortcutRecorder = sender
        let shortcutTarget = sender.shortcutTarget
        sender.startRecording(
            onCommit: { [unowned self] shortcut in
                try updateShortcutHandler(shortcutTarget, shortcut)
            },
            onCancel: { [unowned self] in
                do {
                    try cancelShortcutRecordingHandler()
                } catch {
                    log.error("Shortcut recording cancel failed: \(String(describing: error))")
                }
            },
            onFinish: { [weak self, weak sender] in
                guard self?.activeShortcutRecorder === sender else {
                    return
                }
                self?.activeShortcutRecorder = nil
            }
        )
    }

    @objc private func showAddWorkspacePicker(_ sender: WorkspaceAddButton) {
        let picker = WorkspaceIDPickerViewController(
            unavailableWorkspaceIDs: Set(WorkspaceID.allCases).subtracting(sender.availableWorkspaceIDs),
            displayOptions: snapshotProvider().workspaceDisplayOptions,
            addHandler: addWorkspaceHandler
        )
        presentAsSheet(picker)
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

extension WorkspaceSettingsViewController {
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? WorkspaceNameTextField else {
            return
        }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = name.isEmpty ? nil : name
        guard normalizedName != field.persistedName else {
            return
        }

        do {
            try updateNameHandler(field.workspaceID, normalizedName)
            field.persistedName = normalizedName
            field.stringValue = normalizedName ?? ""
        } catch {
            log.error("Workspace name update failed id=\(field.workspaceID.rawValue): \(String(describing: error))")
            field.stringValue = field.persistedName ?? ""
        }
    }
}
