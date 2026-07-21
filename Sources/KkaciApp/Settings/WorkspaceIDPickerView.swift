import AppKit
import KkaciCore

final class WorkspaceIDPickerView: NSView {
    private static let rows: [[WorkspaceID]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"]
    ]
    private static let rowOffsets: [CGFloat] = [0, 12, 26, 44]

    private var monitorSlotByWorkspaceID: [WorkspaceID: MonitorSlot] = [:]
    private var selectedMonitorSlot: MonitorSlot?
    private var isDeleteMode = false
    private var buttonsByID: [WorkspaceID: WorkspaceIDKeyButton] = [:]
    private let deleteModeButton = WorkspaceDeleteModeButton()
    var onWorkspaceSelected: ((WorkspaceID) -> Void)?
    var onConfiguredWorkspaceSelected: ((WorkspaceID) -> Void)?
    var onWorkspaceRemovalRequested: ((WorkspaceID) -> Void)?
    var onDeleteModeChanged: ((Bool) -> Void)?

    init() {
        super.init(frame: .zero)
        configureDeleteModeButton()
        buildKeyboard()
        apply(monitorSlotByWorkspaceID: [:], selectedMonitorSlot: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        monitorSlotByWorkspaceID: [WorkspaceID: MonitorSlot],
        selectedMonitorSlot: MonitorSlot?,
        isDeleteMode: Bool = false
    ) {
        self.monitorSlotByWorkspaceID = monitorSlotByWorkspaceID
        self.selectedMonitorSlot = selectedMonitorSlot
        self.isDeleteMode = isDeleteMode
        for (workspaceID, button) in buttonsByID {
            button.apply(
                assignment: assignment(for: workspaceID),
                isDeleteMode: isDeleteMode
            )
        }
        deleteModeButton.apply(isDeleteMode: isDeleteMode)
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
        addSubview(deleteModeButton)

        NSLayoutConstraint.activate([
            keyboard.topAnchor.constraint(equalTo: topAnchor),
            keyboard.centerXAnchor.constraint(equalTo: centerXAnchor),
            keyboard.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            keyboard.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: bottomAnchor),
            deleteModeButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            deleteModeButton.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeRow(
        _ workspaceIDs: [WorkspaceID],
        offset: CGFloat
    ) -> NSView {
        let buttons = workspaceIDs.map { workspaceID in
            let button = WorkspaceIDKeyButton(workspaceID: workspaceID)
            button.target = self
            button.action = #selector(selectWorkspace(_:))
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
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    @objc private func toggleDeleteMode(_ sender: WorkspaceDeleteModeButton) {
        onDeleteModeChanged?(sender.state == .on)
    }

    @objc private func selectWorkspace(_ sender: WorkspaceIDKeyButton) {
        switch assignment(for: sender.workspaceID) {
        case .available:
            if !isDeleteMode {
                onWorkspaceSelected?(sender.workspaceID)
            }
        case .selectedDisplay:
            if isDeleteMode {
                onWorkspaceRemovalRequested?(sender.workspaceID)
                return
            }
            onConfiguredWorkspaceSelected?(sender.workspaceID)
        case .otherDisplay:
            break
        }
    }

    private func assignment(for workspaceID: WorkspaceID) -> WorkspaceIDKeyAssignment {
        guard let monitorSlot = monitorSlotByWorkspaceID[workspaceID] else {
            return .available
        }
        guard monitorSlot == selectedMonitorSlot else {
            return .otherDisplay(monitorSlot)
        }
        return .selectedDisplay
    }

    private func configureDeleteModeButton() {
        deleteModeButton.target = self
        deleteModeButton.action = #selector(toggleDeleteMode(_:))
    }
}

private final class WorkspaceDeleteModeButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.toggle)
        isBordered = false
        wantsLayer = true
        setAccessibilityIdentifier("kkaci.settings.workspace.delete-mode")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    func apply(isDeleteMode: Bool) {
        state = isDeleteMode ? .on : .off
        image = NSImage(
            systemSymbolName: isDeleteMode ? "trash.fill" : "trash",
            accessibilityDescription: "Toggle workspace deletion mode"
        )
        image?.size = NSSize(width: 14, height: 14)
        contentTintColor = isDeleteMode ? .systemRed : .labelColor
        toolTip = isDeleteMode
            ? "Delete mode is on. Click an assigned key to remove its workspace."
            : "Enable Delete mode to remove workspaces from this display."
        needsDisplay = true
    }

    override func updateLayer() {
        let isDeleteMode = state == .on
        layer?.backgroundColor = isDeleteMode
            ? NSColor.systemRed.withAlphaComponent(0.24).cgColor
            : NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = isDeleteMode ? NSColor.systemRed.cgColor : NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
    }
}

final class WorkspaceIDKeyButton: NSButton {
    let workspaceID: WorkspaceID
    private var assignment = WorkspaceIDKeyAssignment.available
    private var isDeleteMode = false

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

    func apply(assignment: WorkspaceIDKeyAssignment, isDeleteMode: Bool) {
        self.assignment = assignment
        self.isDeleteMode = isDeleteMode
        switch assignment {
        case .available:
            isEnabled = !isDeleteMode
            toolTip = nil
        case .selectedDisplay:
            isEnabled = true
            toolTip = nil
        case let .otherDisplay(monitorSlot):
            isEnabled = false
            toolTip = "Assigned to Display \(monitorSlot)"
        }
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
        if isDeleteMode, assignment == .selectedDisplay {
            layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.24).cgColor
            layer?.borderColor = NSColor.systemRed.cgColor
            return
        }
        switch assignment {
        case .available:
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        case .selectedDisplay:
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.32).cgColor
            layer?.borderColor = NSColor.controlAccentColor.cgColor
        case .otherDisplay:
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.35).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        }
    }
}

enum WorkspaceIDKeyAssignment: Equatable {
    case available
    case selectedDisplay
    case otherDisplay(MonitorSlot)
}
