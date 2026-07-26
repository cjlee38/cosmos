import AppKit
import CosmosCore

enum SpaceSettingsViewFactory {
    static func configureDisplayViews(
        arrangementView: NSView,
        statusStack: NSStackView,
        editorStack: NSStackView,
        editorTitle: NSTextField,
        spacePicker: NSView
    ) {
        arrangementView.translatesAutoresizingMaskIntoConstraints = false
        configureVerticalStack(statusStack, spacing: 7)
        configureVerticalStack(editorStack, spacing: 12)
        editorTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        editorTitle.textColor = .secondaryLabelColor
        spacePicker.translatesAutoresizingMaskIntoConstraints = false

        let pickerContainer = NSView()
        pickerContainer.addSubview(spacePicker)
        NSLayoutConstraint.activate([
            spacePicker.topAnchor.constraint(equalTo: pickerContainer.topAnchor, constant: 12),
            spacePicker.centerXAnchor.constraint(equalTo: pickerContainer.centerXAnchor),
            spacePicker.leadingAnchor.constraint(greaterThanOrEqualTo: pickerContainer.leadingAnchor, constant: 12),
            spacePicker.trailingAnchor.constraint(lessThanOrEqualTo: pickerContainer.trailingAnchor, constant: -12),
            spacePicker.bottomAnchor.constraint(equalTo: pickerContainer.bottomAnchor, constant: -12)
        ])
        let pickerGroup = SettingsControlFactory.groupBox(content: pickerContainer)
        editorStack.addArrangedSubview(editorTitle)
        editorStack.addArrangedSubview(pickerGroup)
        pickerGroup.widthAnchor.constraint(equalTo: editorStack.widthAnchor).isActive = true
        editorStack.setAccessibilityIdentifier("cosmos.settings.space.editor")
    }

    static func makeDisplaySection(
        arrangementView: NSView,
        statusStack: NSStackView,
        target: AnyObject,
        action: Selector
    ) -> NSView {
        let title = SpaceSettingsControlFactory.headerLabel("Displays")
        let button = NSButton(title: "Display Settings", target: target, action: action)
        button.image = NSImage(
            systemSymbolName: "gearshape",
            accessibilityDescription: "Display Settings"
        )
        button.imagePosition = .imageLeading
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setAccessibilityIdentifier("cosmos.settings.display-settings")

        let header = NSStackView(views: [title, SettingsControlFactory.flexibleSpacer(), button])
        header.orientation = .horizontal
        header.alignment = .centerY
        let content = NSStackView(views: [arrangementView, statusStack])
        configureVerticalStack(content, spacing: 10)
        for arrangedView in content.arrangedSubviews {
            arrangedView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let group = SettingsControlFactory.groupBox(
            content: SettingsControlFactory.padded(content, vertical: 10, horizontal: 10)
        )
        let section = NSStackView(views: [header, group])
        configureVerticalStack(section, spacing: 8)
        header.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        group.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    static func makeInspectorTitleRow(
        spaceID: SpaceID,
        canRemove: Bool,
        target: AnyObject,
        action: Selector
    ) -> NSView {
        let title = SpaceSettingsControlFactory.headerLabel("Space \(spaceID.rawValue)")
        let remove = SpaceSettingsControlFactory.removeButton(
            spaceID: spaceID,
            isEnabled: canRemove,
            target: target,
            action: action
        )
        let row = NSStackView(views: [title, SettingsControlFactory.flexibleSpacer(), remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    static func makeInspectorFields(
        space: SpaceSettingsItem,
        snapshot: SpaceSettingsSnapshot,
        target: AnyObject,
        actions: (monitor: Selector, record: Selector)
    ) -> NSView {
        let selector = SpaceMonitorPopUpButton(
            spaceID: space.id,
            currentMonitorSlot: space.monitorSlot,
            displays: snapshot.displays
        )
        selector.target = target
        selector.action = actions.monitor
        selector.translatesAutoresizingMaskIntoConstraints = false
        selector.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let switchRecorder = SpaceSettingsControlFactory.shortcutRecorder(
            shortcutTarget: .switchSpace(space.id),
            shortcut: space.switchShortcut,
            validationMessage: snapshot.shortcutValidationMessage(for: .switchSpace(space.id)),
            target: target,
            action: actions.record
        )
        let moveRecorder = SpaceSettingsControlFactory.shortcutRecorder(
            shortcutTarget: .moveWindow(space.id),
            shortcut: space.moveShortcut,
            validationMessage: snapshot.shortcutValidationMessage(for: .moveWindow(space.id)),
            target: target,
            action: actions.record
        )
        let fields = NSStackView(views: [
            SpaceSettingsControlFactory.labeledControl(title: "Display", control: selector),
            SpaceSettingsControlFactory.labeledControl(title: "Switch", control: switchRecorder),
            SpaceSettingsControlFactory.labeledControl(title: "Move Window", control: moveRecorder)
        ])
        fields.orientation = .horizontal
        fields.alignment = .bottom
        fields.spacing = 18
        return fields
    }

    static func openDisplaySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Displays-Settings.extension"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func configureVerticalStack(_ stack: NSStackView, spacing: CGFloat) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
    }
}
