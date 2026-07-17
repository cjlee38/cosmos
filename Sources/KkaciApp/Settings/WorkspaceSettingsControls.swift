import AppKit
import KkaciCore

final class WorkspaceMonitorPopUpButton: NSPopUpButton {
    let workspaceID: WorkspaceID
    let currentDisplayID: DisplayID?

    init(
        workspaceID: WorkspaceID,
        currentMonitorSlot: MonitorSlot,
        displays: [WorkspaceSettingsDisplay]
    ) {
        self.workspaceID = workspaceID
        currentDisplayID = displays.first { $0.monitorSlot == currentMonitorSlot }?.id
        super.init(frame: .zero, pullsDown: false)

        setAccessibilityIdentifier("kkaci.settings.workspace.\(workspaceID.rawValue).monitor")
        menu?.autoenablesItems = false
        controlSize = .small
        font = .systemFont(ofSize: 12, weight: .medium)
        for display in displays.sorted(by: displayOrder) {
            let option = WorkspaceDisplayOption(display: display)
            addItem(withTitle: option.title)
            let item = itemArray[itemArray.count - 1]
            item.representedObject = display.id
            item.isEnabled = option.isEnabled
            if display.monitorSlot == currentMonitorSlot {
                select(item)
            }
        }
        if currentDisplayID == nil {
            addItem(withTitle: "Monitor \(currentMonitorSlot) · Disconnected")
            lastItem?.isEnabled = false
            select(lastItem)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func displayOrder(_ lhs: WorkspaceSettingsDisplay, _ rhs: WorkspaceSettingsDisplay) -> Bool {
        (lhs.monitorSlot ?? .max) < (rhs.monitorSlot ?? .max)
    }
}

final class WorkspaceAddButton: NSButton {
    let availableWorkspaceIDs: [WorkspaceID]

    init(availableWorkspaceIDs: [WorkspaceID]) {
        self.availableWorkspaceIDs = availableWorkspaceIDs
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceRemoveButton: NSButton {
    let workspaceID: WorkspaceID

    init(workspaceID: WorkspaceID) {
        self.workspaceID = workspaceID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceNameTextField: NSTextField {
    let workspaceID: WorkspaceID
    var persistedName: String?

    init(workspaceID: WorkspaceID, name: String?) {
        self.workspaceID = workspaceID
        persistedName = name
        super.init(frame: .zero)
        stringValue = name ?? ""
        placeholderString = "Name"
        controlSize = .small
        font = .systemFont(ofSize: 12)
        lineBreakMode = .byTruncatingTail
        setAccessibilityIdentifier("kkaci.settings.workspace.\(workspaceID.rawValue).name")
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum WorkspaceSettingsControlFactory {
    static func identityEditor(
        workspace: WorkspaceSettingsItem,
        delegate: NSTextFieldDelegate
    ) -> NSView {
        let id = NSTextField(labelWithString: workspace.id.rawValue)
        id.font = .systemFont(ofSize: 13, weight: .semibold)
        id.alignment = .center
        id.translatesAutoresizingMaskIntoConstraints = false
        id.widthAnchor.constraint(equalToConstant: 20).isActive = true

        let name = WorkspaceNameTextField(workspaceID: workspace.id, name: workspace.name)
        name.delegate = delegate
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 104).isActive = true

        let row = NSStackView(views: [id, name])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    static func addButton(
        availableWorkspaceIDs: [WorkspaceID],
        target: AnyObject,
        action: Selector
    ) -> NSButton {
        let button = WorkspaceAddButton(availableWorkspaceIDs: availableWorkspaceIDs)
        button.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Workspace")
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.toolTip = "Add Workspace"
        button.target = target
        button.action = action
        button.isEnabled = !availableWorkspaceIDs.isEmpty
        button.setAccessibilityIdentifier("kkaci.settings.workspace.add")
        return button
    }

    static func removeButton(
        workspaceID: WorkspaceID,
        isEnabled: Bool,
        target: AnyObject,
        action: Selector
    ) -> NSButton {
        let button = WorkspaceRemoveButton(workspaceID: workspaceID)
        button.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete Workspace")
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.toolTip = isEnabled
            ? "Delete Workspace \(workspaceID.rawValue)"
            : "At least one workspace is required"
        button.target = target
        button.action = action
        button.isEnabled = isEnabled
        button.setAccessibilityIdentifier("kkaci.settings.workspace.\(workspaceID.rawValue).remove")
        return button
    }
}

final class ShortcutBadgeView: NSView {
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
