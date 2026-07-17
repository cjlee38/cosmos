import AppKit
import KkaciCore

final class WorkspaceIDPickerViewController: NSViewController {
    private let log = Log(category: "settings")
    private let pickerView: WorkspaceIDPickerView
    private let displaySelector = NSPopUpButton()
    private let addHandler: ([WorkspaceID], DisplayID) throws -> Void
    private let addButton = NSButton(title: "Add Workspaces", target: nil, action: nil)

    init(
        unavailableWorkspaceIDs: Set<WorkspaceID>,
        displayOptions: [WorkspaceDisplayOption],
        addHandler: @escaping ([WorkspaceID], DisplayID) throws -> Void
    ) {
        pickerView = WorkspaceIDPickerView(unavailableWorkspaceIDs: unavailableWorkspaceIDs)
        self.addHandler = addHandler
        super.init(nibName: nil, bundle: nil)
        configureDisplaySelector(displayOptions)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 300))

        let title = NSTextField(labelWithString: "Add Workspaces")
        title.font = .systemFont(ofSize: 20, weight: .bold)

        pickerView.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        addButton.target = self
        addButton.action = #selector(addWorkspaces)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.isEnabled = false

        let buttonRow = NSStackView(views: [cancelButton, addButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let footer = NSStackView(views: [displaySelector, NSView(), buttonRow])
        footer.orientation = .horizontal
        footer.alignment = .centerY

        let content = NSStackView(views: [title, pickerView, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)

        pickerView.onSelectionChanged = { [weak self] workspaceIDs in
            self?.addButton.isEnabled = !workspaceIDs.isEmpty
        }

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            pickerView.widthAnchor.constraint(equalTo: content.widthAnchor),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
    }

    @objc private func cancel() {
        dismiss(self)
    }

    @objc private func addWorkspaces() {
        let workspaceIDs = pickerView.selectedWorkspaceIDs
        guard !workspaceIDs.isEmpty,
              let displayID = displaySelector.selectedItem?.representedObject as? DisplayID
        else {
            return
        }
        do {
            try addHandler(workspaceIDs, displayID)
            dismiss(self)
        } catch {
            log.error("Workspace add failed: \(String(describing: error))")
            NSSound.beep()
        }
    }

    private func configureDisplaySelector(_ displayOptions: [WorkspaceDisplayOption]) {
        displaySelector.controlSize = .small
        displaySelector.font = .systemFont(ofSize: 12, weight: .medium)
        displaySelector.menu?.autoenablesItems = false
        displaySelector.setAccessibilityIdentifier("kkaci.workspace-picker.display")
        displaySelector.translatesAutoresizingMaskIntoConstraints = false
        displaySelector.widthAnchor.constraint(equalToConstant: 220).isActive = true
        for option in displayOptions {
            displaySelector.addItem(withTitle: option.title)
            displaySelector.lastItem?.representedObject = option.displayID
            displaySelector.lastItem?.isEnabled = option.isEnabled
        }
        if let firstEnabledItem = displaySelector.itemArray.first(where: \.isEnabled) {
            displaySelector.select(firstEnabledItem)
        }
    }
}

final class WorkspaceIDPickerView: NSView {
    private static let rows: [[WorkspaceID]] = [
        ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    private static let rowOffsets: [CGFloat] = [0, 12, 26, 44]

    private let unavailableWorkspaceIDs: Set<WorkspaceID>
    private var selectedIDs: Set<WorkspaceID> = []
    private var buttonsByID: [WorkspaceID: WorkspaceIDKeyButton] = [:]
    var onSelectionChanged: (([WorkspaceID]) -> Void)?

    init(unavailableWorkspaceIDs: Set<WorkspaceID>) {
        self.unavailableWorkspaceIDs = unavailableWorkspaceIDs
        super.init(frame: .zero)
        buildKeyboard()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var selectedWorkspaceIDs: [WorkspaceID] {
        WorkspaceID.allCases.filter(selectedIDs.contains)
    }

    private func buildKeyboard() {
        let rowViews = Self.rows.enumerated().map { index, workspaceIDs in
            makeRow(workspaceIDs, offset: Self.rowOffsets[index])
        }
        let keyboard = NSStackView(views: rowViews)
        keyboard.orientation = .vertical
        keyboard.alignment = .leading
        keyboard.spacing = 8
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(keyboard)

        NSLayoutConstraint.activate([
            keyboard.topAnchor.constraint(equalTo: topAnchor),
            keyboard.leadingAnchor.constraint(equalTo: leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeRow(_ workspaceIDs: [WorkspaceID], offset: CGFloat) -> NSView {
        let buttons = workspaceIDs.map { workspaceID in
            let button = WorkspaceIDKeyButton(workspaceID: workspaceID)
            button.target = self
            button.action = #selector(toggleWorkspace(_:))
            button.apply(isSelected: false, isUnavailable: unavailableWorkspaceIDs.contains(workspaceID))
            buttonsByID[workspaceID] = button
            return button
        }
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 40),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: offset),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    @objc private func toggleWorkspace(_ sender: WorkspaceIDKeyButton) {
        if selectedIDs.contains(sender.workspaceID) {
            selectedIDs.remove(sender.workspaceID)
        } else {
            selectedIDs.insert(sender.workspaceID)
        }
        sender.apply(isSelected: selectedIDs.contains(sender.workspaceID), isUnavailable: false)
        onSelectionChanged?(selectedWorkspaceIDs)
    }
}

final class WorkspaceIDKeyButton: NSButton {
    let workspaceID: WorkspaceID

    init(workspaceID: WorkspaceID) {
        self.workspaceID = workspaceID
        super.init(frame: .zero)
        title = workspaceID.rawValue
        font = .systemFont(ofSize: 13, weight: .semibold)
        isBordered = false
        wantsLayer = true
        setAccessibilityIdentifier("kkaci.workspace-picker.\(workspaceID.rawValue)")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 40),
            heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    func apply(isSelected: Bool, isUnavailable: Bool) {
        state = isSelected ? .on : .off
        isEnabled = !isUnavailable
        alphaValue = isUnavailable ? 0.34 : 1
        contentTintColor = isSelected ? .selectedControlTextColor : .labelColor
        needsDisplay = true
    }

    override func updateLayer() {
        let isSelected = state == .on
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
    }
}
