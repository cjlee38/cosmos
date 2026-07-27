import AppKit
import CosmosCore

final class SpaceSettingsViewController: NSViewController {
    private let log = Log(category: "settings")
    private let service: any SpaceSettingsServing
    private let shortcutRecordingController: ShortcutRecordingController
    private let displayArrangementView = SpaceDisplayArrangementView()
    private let displayStatusStack = NSStackView()
    private let displayEditorStack = NSStackView()
    private let displayEditorTitle = NSTextField(labelWithString: "")
    private let spacePicker = SpaceIDPickerView()
    private let inspectorSection = NSStackView()
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var configErrorNotice = SpaceSettingsControlFactory.configErrorNotice(label: configErrorLabel)
    private var selectedDisplayID: DisplayID?
    private var selectedSpaceID: SpaceID?
    private var isAddingSpace = false
    private var isDeleteMode = false

    init(
        service: any SpaceSettingsServing,
        shortcutRecordingController: ShortcutRecordingController? = nil
    ) {
        self.service = service
        self.shortcutRecordingController = shortcutRecordingController
            ?? ShortcutRecordingController(service: service)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))

        let (scrollView, documentView) = GeneralSettingsViewFactory.makeScrollView()
        view.addSubview(scrollView)

        SpaceSettingsViewFactory.configureDisplayViews(
            arrangementView: displayArrangementView,
            statusStack: displayStatusStack,
            editorStack: displayEditorStack,
            editorTitle: displayEditorTitle,
            spacePicker: spacePicker
        )
        configureVerticalStack(inspectorSection, spacing: 8)

        let root = NSStackView(views: [
            SettingsControlFactory.header(title: "Spaces", symbolName: "rectangle.3.group.fill"),
            configErrorNotice,
            SpaceSettingsViewFactory.makeDisplaySection(
                arrangementView: displayArrangementView,
                statusStack: displayStatusStack,
                target: self,
                action: #selector(openDisplaySettings)
            ),
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
        guard isViewLoaded, shortcutRecordingController.cancel() else {
            return
        }
        apply(service.snapshot())
    }
}

private extension SpaceSettingsViewController {
    private func wireActions() {
        displayArrangementView.onDisplaySelected = { [weak self] displayID in
            self?.openSpaceEditor(for: displayID)
        }
        displayArrangementView.onSelectionCleared = { [weak self] in
            self?.clearSpaceSelection()
        }
        displayArrangementView.onSpaceSelected = { [weak self] spaceID in
            self?.selectSpace(spaceID)
        }
        displayArrangementView.onSpaceMoved = { [weak self] spaceID, displayID in
            self?.moveSpace(spaceID, to: displayID)
        }
        spacePicker.onSpaceSelected = { [weak self] spaceID in
            self?.addSpace(spaceID)
        }
        spacePicker.onConfiguredSpaceSelected = { [weak self] spaceID in
            self?.selectSpace(spaceID, keepSpaceEditorOpen: true)
        }
        spacePicker.onSpaceRemovalRequested = { [weak self] spaceID in
            self?.requestSpaceRemoval(spaceID)
        }
        spacePicker.onDeleteModeChanged = { [weak self] isDeleteMode in
            guard let self else {
                return
            }
            self.isDeleteMode = isDeleteMode
            apply(service.snapshot())
        }
    }

    private func apply(_ snapshot: SpaceSettingsSnapshot) {
        let displayIDs = Set(snapshot.displays.map(\.id))
        if let selectedDisplayID, !displayIDs.contains(selectedDisplayID) {
            self.selectedDisplayID = nil
        }
        selectedDisplayID = selectedDisplayID ?? snapshot.displays.first?.id

        if let selectedSpaceID,
           !snapshot.spaces.contains(where: { $0.id == selectedSpaceID }) {
            self.selectedSpaceID = nil
        }

        displayArrangementView.apply(
            snapshot.displays,
            selectedDisplayID: isAddingSpace ? selectedDisplayID : nil,
            selectedSpaceID: selectedSpaceID,
            isEditable: snapshot.isEditable
        )
        spacePicker.apply(
            monitorSlotBySpaceID: Dictionary(
                uniqueKeysWithValues: snapshot.spaces.map { ($0.id, $0.monitorSlot) }
            ),
            selectedMonitorSlot: snapshot.displays
                .first(where: { $0.id == selectedDisplayID })?
                .monitorSlot,
            isDeleteMode: isDeleteMode,
            isEditable: snapshot.isEditable
        )
        updateDisplayEditor(snapshot)
        rebuildDisplayStatus(snapshot)
        rebuildInspector(snapshot)
        updateEditingState(snapshot)
    }

    private func updateDisplayEditor(_ snapshot: SpaceSettingsSnapshot) {
        displayEditorStack.isHidden = !isAddingSpace
        guard let display = snapshot.displays.first(where: { $0.id == selectedDisplayID }) else {
            displayEditorTitle.stringValue = "Add Space"
            return
        }
        displayEditorTitle.stringValue = "Add Space to \(display.monitorSlot) · \(display.name)"
    }

    private func rebuildDisplayStatus(_ snapshot: SpaceSettingsSnapshot) {
        removeArrangedSubviews(from: displayStatusStack)
        for monitorSlot in snapshot.disconnectedMonitorSlots {
            let spaceIDs = snapshot.spaces
                .filter { $0.monitorSlot == monitorSlot }
                .map(\.id.rawValue)
                .joined(separator: ", ")
            displayStatusStack.addArrangedSubview(SpaceSettingsControlFactory.statusRow(
                symbol: "rectangle.slash",
                text: "Monitor \(monitorSlot) · Disconnected    \(spaceIDs)",
                color: .secondaryLabelColor
            ))
        }
        displayStatusStack.isHidden = displayStatusStack.arrangedSubviews.isEmpty
    }

    private func rebuildInspector(_ snapshot: SpaceSettingsSnapshot) {
        removeArrangedSubviews(from: inspectorSection)
        guard let selectedSpaceID,
              let space = snapshot.spaces.first(where: { $0.id == selectedSpaceID })
        else {
            inspectorSection.isHidden = true
            return
        }

        let titleRow = SpaceSettingsViewFactory.makeInspectorTitleRow(
            spaceID: selectedSpaceID,
            canRemove: snapshot.spaces.count > 1,
            target: self,
            action: #selector(removeSpace(_:))
        )
        let fields = SpaceSettingsViewFactory.makeInspectorFields(
            space: space,
            snapshot: snapshot,
            target: self,
            actions: (
                monitor: #selector(monitorSelectionChanged(_:)),
                record: #selector(beginShortcutRecording(_:))
            )
        )
        let content = NSStackView(views: [titleRow, fields])
        configureVerticalStack(content, spacing: 10)
        let group = SettingsControlFactory.groupBox(
            content: SettingsControlFactory.padded(content, vertical: 10, horizontal: 14)
        )
        inspectorSection.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: inspectorSection.widthAnchor).isActive = true
        inspectorSection.setAccessibilityIdentifier("cosmos.settings.space.inspector")
        inspectorSection.isHidden = false
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

    private func updateEditingState(_ snapshot: SpaceSettingsSnapshot) {
        configErrorLabel.stringValue = snapshot.isEditable
            ? ""
            : "Configuration is invalid. Fix config.yaml in General before editing spaces."
        configErrorNotice.isHidden = snapshot.isEditable
        if !snapshot.isEditable {
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

    private func clearSpaceSelection() {
        selectedSpaceID = nil
        apply(service.snapshot())
    }

    private func openSpaceEditor(for displayID: DisplayID) {
        selectedDisplayID = displayID
        selectedSpaceID = nil
        isAddingSpace = true
        isDeleteMode = false
        apply(service.snapshot())
        scrollToVisible(displayEditorStack)
    }

    private func selectSpace(
        _ spaceID: SpaceID,
        keepSpaceEditorOpen: Bool = false
    ) {
        selectedSpaceID = spaceID
        if !keepSpaceEditorOpen {
            isAddingSpace = false
            isDeleteMode = false
        }
        apply(service.snapshot())
        scrollToVisible(inspectorSection)
    }

    private func addSpace(_ spaceID: SpaceID) {
        guard let displayID = selectedDisplayID else {
            return
        }
        selectedSpaceID = spaceID
        do {
            try service.addSpaces([spaceID], displayID: displayID)
            scrollToVisible(inspectorSection)
        } catch {
            selectedSpaceID = nil
            isAddingSpace = true
            log.error("Space add failed id=\(spaceID.rawValue): \(String(describing: error))")
            refresh()
        }
    }

    private func moveSpace(_ spaceID: SpaceID, to displayID: DisplayID) {
        let snapshot = service.snapshot()
        guard snapshot.spaces.first(where: { $0.id == spaceID })?.monitorSlot
            != snapshot.displays.first(where: { $0.id == displayID })?.monitorSlot
        else {
            return
        }
        selectedSpaceID = spaceID
        selectedDisplayID = displayID
        do {
            try service.updateMonitor(spaceID, displayID: displayID)
        } catch {
            log.error(
                "Space drag failed space=\(spaceID.rawValue) "
                    + "display=\(displayID): \(String(describing: error))"
            )
            refresh()
        }
    }

    @objc private func monitorSelectionChanged(_ sender: SpaceMonitorPopUpButton) {
        guard let displayID = sender.selectedItem?.representedObject as? DisplayID,
              displayID != sender.currentDisplayID
        else {
            return
        }

        selectedDisplayID = displayID
        do {
            try service.updateMonitor(sender.spaceID, displayID: displayID)
        } catch {
            log.error(
                "Space monitor update failed space=\(sender.spaceID.rawValue) "
                    + "display=\(displayID): \(String(describing: error))"
            )
            refresh()
        }
    }

    @objc private func beginShortcutRecording(_ sender: ShortcutRecorderButton) {
        shortcutRecordingController.begin(sender)
    }

    @objc private func removeSpace(_ sender: SpaceRemoveButton) {
        requestSpaceRemoval(sender.spaceID)
    }

    private func requestSpaceRemoval(_ spaceID: SpaceID) {
        let snapshot = service.snapshot()
        guard snapshot.spaces.count > 1,
              let space = snapshot.spaces.first(where: { $0.id == spaceID })
        else {
            return
        }
        guard space.windowCount > 0 else {
            performSpaceRemoval(spaceID)
            return
        }

        presentSpaceRemovalConfirmation(spaceID)
    }

    private func presentSpaceRemovalConfirmation(_ spaceID: SpaceID) {
        guard let window = view.window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete Space \(spaceID.rawValue)?"
        alert.informativeText = "Its windows will move to the current space."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.buttons[0].hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else {
                return
            }
            self?.performSpaceRemoval(spaceID)
        }
    }

    private func performSpaceRemoval(_ spaceID: SpaceID) {
        let previousSelection = selectedSpaceID
        if selectedSpaceID == spaceID {
            selectedSpaceID = nil
        }
        do {
            try service.removeSpace(spaceID)
        } catch {
            selectedSpaceID = previousSelection
            log.error("Space removal failed id=\(spaceID.rawValue): \(String(describing: error))")
            refresh()
        }
    }

    private func scrollToVisible(_ section: NSView) {
        view.layoutSubtreeIfNeeded()
        section.scrollToVisible(section.bounds)
    }

    @objc private func openDisplaySettings() {
        SpaceSettingsViewFactory.openDisplaySettings()
    }
}
