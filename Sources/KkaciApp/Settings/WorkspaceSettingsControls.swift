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
    static func header() -> NSView {
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

    static func configErrorNotice(label: NSTextField) -> NSStackView {
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: "exclamationmark.triangle.fill",
            accessibilityDescription: "Invalid configuration"
        )
        icon.contentTintColor = .systemRed
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

        label.textColor = .systemRed
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.setAccessibilityIdentifier("kkaci.settings.workspace.config-error")
        let notice = NSStackView(views: [icon, label])
        notice.orientation = .horizontal
        notice.alignment = .centerY
        notice.spacing = 7
        notice.isHidden = true
        return notice
    }

    static func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    static func statusRow(symbol: String, text: String, color: NSColor) -> NSView {
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

    static func titledSection(title: String, content: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        let section = NSStackView(views: [titleLabel, content])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        content.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    static func switcherRow(
        title: String,
        shortcuts: SwitcherSettingsShortcuts,
        targets: (next: ShortcutTarget, previous: ShortcutTarget),
        validationMessages: [ShortcutTarget: String],
        action: (target: AnyObject, selector: Selector)
    ) -> NSView {
        let title = valueLabel(title)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let next = labeledShortcut(
            title: "Next",
            shortcutTarget: targets.next,
            shortcut: shortcuts.next,
            validationMessage: validationMessages[targets.next],
            action: action
        )
        let previous = labeledShortcut(
            title: "Previous",
            shortcutTarget: targets.previous,
            shortcut: shortcuts.previous,
            validationMessage: validationMessages[targets.previous],
            action: action
        )
        let row = NSStackView(views: [title, spacer, next, previous])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    static func shortcutRecorder(
        shortcutTarget: ShortcutTarget,
        shortcut: String?,
        validationMessage: String? = nil,
        target: AnyObject,
        action: Selector
    ) -> ShortcutRecorderControl {
        let button = ShortcutRecorderButton(
            shortcutTarget: shortcutTarget,
            shortcut: shortcut,
            validationMessage: validationMessage
        )
        button.target = target
        button.action = action
        return ShortcutRecorderControl(
            recorderButton: button,
            validationMessage: validationMessage
        )
    }

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

    private static func labeledShortcut(
        title: String,
        shortcutTarget: ShortcutTarget,
        shortcut: String?,
        validationMessage: String?,
        action: (target: AnyObject, selector: Selector)
    ) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let control = shortcutRecorder(
            shortcutTarget: shortcutTarget,
            shortcut: shortcut,
            validationMessage: validationMessage,
            target: action.target,
            action: action.selector
        )
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private static func valueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
