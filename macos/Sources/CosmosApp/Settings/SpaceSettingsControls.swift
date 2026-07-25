import AppKit
import CosmosCore

final class SpaceMonitorPopUpButton: NSPopUpButton {
    let spaceID: SpaceID
    let currentDisplayID: DisplayID?

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height *= 1.5
        return size
    }

    init(
        spaceID: SpaceID,
        currentMonitorSlot: MonitorSlot,
        displays: [SpaceSettingsDisplay]
    ) {
        self.spaceID = spaceID
        currentDisplayID = displays.first { $0.monitorSlot == currentMonitorSlot }?.id
        super.init(frame: .zero, pullsDown: false)

        setAccessibilityIdentifier("cosmos.settings.space.\(spaceID.rawValue).monitor")
        menu?.autoenablesItems = false
        bezelStyle = .badge
        controlSize = .large
        font = .systemFont(ofSize: 12, weight: .medium)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        layer?.cornerCurve = .continuous
        for display in displays.sorted(by: displayOrder) {
            let option = SpaceDisplayOption(display: display)
            addItem(withTitle: option.title)
            let item = itemArray[itemArray.count - 1]
            item.representedObject = display.id
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

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func displayOrder(_ lhs: SpaceSettingsDisplay, _ rhs: SpaceSettingsDisplay)
        -> Bool {
        lhs.monitorSlot < rhs.monitorSlot
    }
}

final class SpaceRemoveButton: NSButton {
    let spaceID: SpaceID

    init(spaceID: SpaceID) {
        self.spaceID = spaceID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

enum SpaceSettingsControlFactory {
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
        label.setAccessibilityIdentifier("cosmos.settings.space.config-error")
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

    static func switcherRow(
        title: String,
        shortcut: String?,
        shortcutTarget: ShortcutTarget,
        validationMessages: [ShortcutTarget: String],
        action: (target: AnyObject, selector: Selector)
    ) -> NSView {
        let title = valueLabel(title)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let recorder = shortcutRecorder(
            shortcutTarget: shortcutTarget,
            shortcut: shortcut,
            validationMessage: validationMessages[shortcutTarget],
            target: action.target,
            action: action.selector
        )
        let row = NSStackView(views: [title, spacer, recorder])
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

    static func labeledControl(title: String, control: NSView) -> NSView {
        let label = headerLabel(title)
        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        return stack
    }

    static func removeButton(
        spaceID: SpaceID,
        isEnabled: Bool,
        target: AnyObject,
        action: Selector
    ) -> NSButton {
        let button = SpaceRemoveButton(spaceID: spaceID)
        button.image = NSImage(
            systemSymbolName: "trash", accessibilityDescription: "Delete Space"
        )
        button.imagePosition = .imageOnly
        button.bezelStyle = .accessoryBarAction
        button.toolTip =
            isEnabled
                ? "Delete Space \(spaceID.rawValue)"
                : "At least one space is required"
        button.target = target
        button.action = action
        button.isEnabled = isEnabled
        button.setAccessibilityIdentifier("cosmos.settings.space.\(spaceID.rawValue).remove")
        return button
    }

    private static func valueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}
