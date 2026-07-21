import AppKit
import KkaciCore

final class WorkspaceSettingsViewController: NSViewController {
    private let log = Log(category: "settings")
    private let service: any WorkspaceSettingsServing
    private let shortcutRecordingController: ShortcutRecordingController
    private let displayArrangementView = WorkspaceDisplayArrangementView()
    private let displayStatusStack = NSStackView()
    private let displayEditorStack = NSStackView()
    private let displayEditorTitle = NSTextField(labelWithString: "")
    private let workspacePicker = WorkspaceIDPickerView(unavailableWorkspaceIDs: [])
    private let inspectorSection = NSStackView()
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var configErrorNotice = WorkspaceSettingsControlFactory.configErrorNotice(label: configErrorLabel)
    private var selectedDisplayID: DisplayID?
    private var selectedWorkspaceID: WorkspaceID?
    private var isAddingWorkspace = false

    init(
        service: any WorkspaceSettingsServing,
        shortcutRecordingController: ShortcutRecordingController? = nil
    ) {
        self.service = service
        self.shortcutRecordingController = shortcutRecordingController
            ?? ShortcutRecordingController(service: service)
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

        configureDisplayViews()
        configureVerticalStack(inspectorSection, spacing: 8)

        let root = NSStackView(views: [
            SettingsControlFactory.header(title: "Workspaces", symbolName: "rectangle.3.group.fill"),
            configErrorNotice,
            makeDisplaySection(),
            displayEditorStack,
            inspectorSection
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
            root.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24)
        ])
        for section in root.arrangedSubviews.dropFirst() {
            section.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        wireActions()
        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }
        guard shortcutRecordingController.cancel() else {
            return
        }
        apply(service.snapshot())
    }
}

private extension WorkspaceSettingsViewController {
    private func configureDisplayViews() {
        displayArrangementView.translatesAutoresizingMaskIntoConstraints = false
        displayArrangementView.heightAnchor.constraint(equalToConstant: 210).isActive = true
        configureVerticalStack(displayStatusStack, spacing: 7)
        configureVerticalStack(displayEditorStack, spacing: 12)

        displayEditorTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        displayEditorTitle.textColor = .secondaryLabelColor
        workspacePicker.translatesAutoresizingMaskIntoConstraints = false

        let pickerContainer = NSView()
        pickerContainer.addSubview(workspacePicker)
        NSLayoutConstraint.activate([
            workspacePicker.topAnchor.constraint(equalTo: pickerContainer.topAnchor, constant: 12),
            workspacePicker.centerXAnchor.constraint(equalTo: pickerContainer.centerXAnchor),
            workspacePicker.leadingAnchor.constraint(greaterThanOrEqualTo: pickerContainer.leadingAnchor, constant: 12),
            workspacePicker.trailingAnchor.constraint(lessThanOrEqualTo: pickerContainer.trailingAnchor, constant: -12),
            workspacePicker.bottomAnchor.constraint(equalTo: pickerContainer.bottomAnchor, constant: -12)
        ])
        let pickerGroup = SettingsControlFactory.groupBox(content: pickerContainer)
        displayEditorStack.addArrangedSubview(displayEditorTitle)
        displayEditorStack.addArrangedSubview(pickerGroup)
        pickerGroup.widthAnchor.constraint(equalTo: displayEditorStack.widthAnchor).isActive = true
        displayEditorStack.setAccessibilityIdentifier("kkaci.settings.workspace.editor")
    }

    private func makeDisplaySection() -> NSView {
        let title = WorkspaceSettingsControlFactory.headerLabel("Displays")

        let content = NSStackView(views: [displayArrangementView, displayStatusStack])
        configureVerticalStack(content, spacing: 10)
        for arrangedView in content.arrangedSubviews {
            arrangedView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let group = SettingsControlFactory.groupBox(
            content: SettingsControlFactory.padded(content, vertical: 10, horizontal: 10)
        )
        let section = NSStackView(views: [title, group])
        configureVerticalStack(section, spacing: 8)
        group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func makeScrollView() -> (scrollView: NSScrollView, documentView: NSView) {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        let documentView = WorkspaceSettingsDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        return (scrollView, documentView)
    }

    private func wireActions() {
        displayArrangementView.onDisplaySelected = { [weak self] displayID in
            self?.openWorkspaceEditor(for: displayID)
        }
        displayArrangementView.onSelectionCleared = { [weak self] in
            self?.clearWorkspaceSelection()
        }
        displayArrangementView.onWorkspaceSelected = { [weak self] workspaceID in
            self?.selectWorkspace(workspaceID)
        }
        displayArrangementView.onWorkspaceMoved = { [weak self] workspaceID, displayID in
            self?.moveWorkspace(workspaceID, to: displayID)
        }
        workspacePicker.onWorkspaceSelected = { [weak self] workspaceID in
            self?.addWorkspace(workspaceID)
        }
        workspacePicker.onConfiguredWorkspaceSelected = { [weak self] workspaceID in
            self?.requestWorkspaceRemoval(workspaceID)
        }
    }

    private func apply(_ snapshot: WorkspaceSettingsSnapshot) {
        let displayIDs = Set(snapshot.displays.map(\.id))
        if let selectedDisplayID, !displayIDs.contains(selectedDisplayID) {
            self.selectedDisplayID = nil
        }
        selectedDisplayID = selectedDisplayID ?? snapshot.displays.first?.id

        if let selectedWorkspaceID,
           !snapshot.workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
            self.selectedWorkspaceID = nil
        }

        displayArrangementView.apply(
            snapshot.displays,
            selectedDisplayID: isAddingWorkspace ? selectedDisplayID : nil,
            selectedWorkspaceID: selectedWorkspaceID,
            isEditable: snapshot.isEditable
        )
        workspacePicker.apply(unavailableWorkspaceIDs: Set(snapshot.workspaces.map(\.id)))
        updateDisplayEditor(snapshot)
        rebuildDisplayStatus(snapshot)
        rebuildInspector(snapshot)
        updateEditingState(snapshot)
    }

    private func updateDisplayEditor(_ snapshot: WorkspaceSettingsSnapshot) {
        displayEditorStack.isHidden = !isAddingWorkspace
        guard let display = snapshot.displays.first(where: { $0.id == selectedDisplayID }) else {
            displayEditorTitle.stringValue = "Add Workspace"
            return
        }
        displayEditorTitle.stringValue = "Add Workspace to \(display.monitorSlot) · \(display.name)"
    }

    private func rebuildDisplayStatus(_ snapshot: WorkspaceSettingsSnapshot) {
        removeArrangedSubviews(from: displayStatusStack)
        for monitorSlot in snapshot.disconnectedMonitorSlots {
            let workspaceIDs = snapshot.workspaces
                .filter { $0.monitorSlot == monitorSlot }
                .map(\.id.rawValue)
                .joined(separator: ", ")
            displayStatusStack.addArrangedSubview(WorkspaceSettingsControlFactory.statusRow(
                symbol: "rectangle.slash",
                text: "Monitor \(monitorSlot) · Disconnected    \(workspaceIDs)",
                color: .secondaryLabelColor
            ))
        }
        displayStatusStack.isHidden = displayStatusStack.arrangedSubviews.isEmpty
    }

    private func rebuildInspector(_ snapshot: WorkspaceSettingsSnapshot) {
        removeArrangedSubviews(from: inspectorSection)
        guard let selectedWorkspaceID,
              let workspace = snapshot.workspaces.first(where: { $0.id == selectedWorkspaceID })
        else {
            inspectorSection.isHidden = true
            return
        }

        let title = WorkspaceSettingsControlFactory.headerLabel("Workspace \(selectedWorkspaceID.rawValue)")
        let remove = WorkspaceSettingsControlFactory.removeButton(
            workspaceID: selectedWorkspaceID,
            isEnabled: snapshot.workspaces.count > 1,
            target: self,
            action: #selector(removeWorkspace(_:))
        )
        let titleRow = NSStackView(views: [title, SettingsControlFactory.flexibleSpacer(), remove])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY

        let selector = monitorSelector(workspace: workspace, displays: snapshot.displays)
        selector.translatesAutoresizingMaskIntoConstraints = false
        selector.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let switchRecorder = WorkspaceSettingsControlFactory.shortcutRecorder(
            shortcutTarget: .switchWorkspace(workspace.id),
            shortcut: workspace.switchShortcut,
            validationMessage: snapshot.shortcutValidationMessage(for: .switchWorkspace(workspace.id)),
            target: self,
            action: #selector(beginShortcutRecording(_:))
        )
        let moveRecorder = WorkspaceSettingsControlFactory.shortcutRecorder(
            shortcutTarget: .moveWindow(workspace.id),
            shortcut: workspace.moveShortcut,
            validationMessage: snapshot.shortcutValidationMessage(for: .moveWindow(workspace.id)),
            target: self,
            action: #selector(beginShortcutRecording(_:))
        )
        let fields = NSStackView(views: [
            WorkspaceSettingsControlFactory.labeledControl(title: "Display", control: selector),
            WorkspaceSettingsControlFactory.labeledControl(title: "Switch", control: switchRecorder),
            WorkspaceSettingsControlFactory.labeledControl(title: "Move Window", control: moveRecorder)
        ])
        fields.orientation = .horizontal
        fields.alignment = .bottom
        fields.spacing = 18

        let content = NSStackView(views: [titleRow, fields])
        configureVerticalStack(content, spacing: 10)
        let group = SettingsControlFactory.groupBox(
            content: SettingsControlFactory.padded(content, vertical: 10, horizontal: 14)
        )
        inspectorSection.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: inspectorSection.widthAnchor).isActive = true
        inspectorSection.setAccessibilityIdentifier("kkaci.settings.workspace.inspector")
        inspectorSection.isHidden = false
    }

    private func monitorSelector(
        workspace: WorkspaceSettingsItem,
        displays: [WorkspaceSettingsDisplay]
    ) -> WorkspaceMonitorPopUpButton {
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
            disableControls(in: displayEditorStack)
            disableControls(in: inspectorSection)
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

    private func clearWorkspaceSelection() {
        selectedWorkspaceID = nil
        apply(service.snapshot())
    }

    private func openWorkspaceEditor(for displayID: DisplayID) {
        selectedDisplayID = displayID
        selectedWorkspaceID = nil
        isAddingWorkspace = true
        apply(service.snapshot())
    }

    private func selectWorkspace(
        _ workspaceID: WorkspaceID,
        keepWorkspaceEditorOpen: Bool = false
    ) {
        selectedWorkspaceID = workspaceID
        if !keepWorkspaceEditorOpen {
            isAddingWorkspace = false
        }
        apply(service.snapshot())
    }

    private func addWorkspace(_ workspaceID: WorkspaceID) {
        guard let displayID = selectedDisplayID else {
            return
        }
        selectedWorkspaceID = workspaceID
        do {
            try service.addWorkspaces([workspaceID], displayID: displayID)
        } catch {
            selectedWorkspaceID = nil
            isAddingWorkspace = true
            log.error("Workspace add failed id=\(workspaceID.rawValue): \(String(describing: error))")
            refresh()
        }
    }

    private func moveWorkspace(_ workspaceID: WorkspaceID, to displayID: DisplayID) {
        let snapshot = service.snapshot()
        guard snapshot.workspaces.first(where: { $0.id == workspaceID })?.monitorSlot
            != snapshot.displays.first(where: { $0.id == displayID })?.monitorSlot
        else {
            return
        }
        selectedWorkspaceID = workspaceID
        selectedDisplayID = displayID
        do {
            try service.updateMonitor(workspaceID, displayID: displayID)
        } catch {
            log.error(
                "Workspace drag failed workspace=\(workspaceID.rawValue) "
                    + "display=\(displayID): \(String(describing: error))"
            )
            refresh()
        }
    }

    @objc private func monitorSelectionChanged(_ sender: WorkspaceMonitorPopUpButton) {
        guard let displayID = sender.selectedItem?.representedObject as? DisplayID,
              displayID != sender.currentDisplayID
        else {
            return
        }

        selectedDisplayID = displayID
        do {
            try service.updateMonitor(sender.workspaceID, displayID: displayID)
        } catch {
            log.error(
                "Workspace monitor update failed workspace=\(sender.workspaceID.rawValue) "
                    + "display=\(displayID): \(String(describing: error))"
            )
            refresh()
        }
    }

    @objc private func beginShortcutRecording(_ sender: ShortcutRecorderButton) {
        shortcutRecordingController.begin(sender)
    }

    @objc private func removeWorkspace(_ sender: WorkspaceRemoveButton) {
        requestWorkspaceRemoval(sender.workspaceID)
    }

    private func requestWorkspaceRemoval(_ workspaceID: WorkspaceID) {
        let snapshot = service.snapshot()
        guard snapshot.workspaces.count > 1,
              let workspace = snapshot.workspaces.first(where: { $0.id == workspaceID })
        else {
            return
        }
        guard workspace.windowCount > 0 else {
            performWorkspaceRemoval(workspaceID)
            return
        }

        presentWorkspaceRemovalConfirmation(workspaceID)
    }

    private func presentWorkspaceRemovalConfirmation(_ workspaceID: WorkspaceID) {
        guard let window = view.window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete Workspace \(workspaceID.rawValue)?"
        alert.informativeText = "Its windows will move to the current workspace."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.buttons[0].hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            self?.performWorkspaceRemoval(workspaceID)
        }
    }

    private func performWorkspaceRemoval(_ workspaceID: WorkspaceID) {
        let previousSelection = selectedWorkspaceID
        if selectedWorkspaceID == workspaceID {
            selectedWorkspaceID = nil
        }
        do {
            try service.removeWorkspace(workspaceID)
        } catch {
            selectedWorkspaceID = previousSelection
            log.error("Workspace removal failed id=\(workspaceID.rawValue): \(String(describing: error))")
            refresh()
        }
    }
}

private final class WorkspaceSettingsDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}
