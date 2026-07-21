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

    private var unavailableWorkspaceIDs: Set<WorkspaceID>
    private var buttonsByID: [WorkspaceID: WorkspaceIDKeyButton] = [:]
    var onWorkspaceSelected: ((WorkspaceID) -> Void)?
    var onConfiguredWorkspaceSelected: ((WorkspaceID) -> Void)?

    init(unavailableWorkspaceIDs: Set<WorkspaceID>) {
        self.unavailableWorkspaceIDs = unavailableWorkspaceIDs
        super.init(frame: .zero)
        buildKeyboard()
        apply(unavailableWorkspaceIDs: unavailableWorkspaceIDs)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(unavailableWorkspaceIDs: Set<WorkspaceID>) {
        self.unavailableWorkspaceIDs = unavailableWorkspaceIDs
        for (workspaceID, button) in buttonsByID {
            button.apply(isConfigured: unavailableWorkspaceIDs.contains(workspaceID))
        }
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
            keyboard.centerXAnchor.constraint(equalTo: centerXAnchor),
            keyboard.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            keyboard.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            keyboard.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func makeRow(_ workspaceIDs: [WorkspaceID], offset: CGFloat) -> NSView {
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

    @objc private func selectWorkspace(_ sender: WorkspaceIDKeyButton) {
        if unavailableWorkspaceIDs.contains(sender.workspaceID) {
            onConfiguredWorkspaceSelected?(sender.workspaceID)
            return
        }
        onWorkspaceSelected?(sender.workspaceID)
    }
}

final class WorkspaceIDKeyButton: NSButton {
    let workspaceID: WorkspaceID
    private var isConfigured = false

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

    func apply(isConfigured: Bool) {
        self.isConfigured = isConfigured
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = isConfigured
            ? NSColor.controlAccentColor.withAlphaComponent(0.32).cgColor
            : NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = isConfigured
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
    }
}
