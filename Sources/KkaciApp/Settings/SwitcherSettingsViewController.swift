import AppKit

final class SwitcherSettingsViewController: NSViewController {
    private let store: AppSettingsStore
    private let settingsService: any WorkspaceSettingsServing
    private let shortcutRecordingController: ShortcutRecordingController
    private let onChange: () -> Void

    private let windowSwitcherSizeSlider = NSSlider(
        value: SwitcherSizeRange.defaultWindow,
        minValue: SwitcherSizeRange.window.lowerBound,
        maxValue: SwitcherSizeRange.window.upperBound,
        target: nil,
        action: nil
    )
    private let workspaceSwitcherSizeSlider = NSSlider(
        value: SwitcherSizeRange.defaultWorkspace,
        minValue: SwitcherSizeRange.workspace.lowerBound,
        maxValue: SwitcherSizeRange.workspace.upperBound,
        target: nil,
        action: nil
    )
    private let windowSwitcherSizeValueLabel = NSTextField(labelWithString: "")
    private let workspaceSwitcherSizeValueLabel = NSTextField(labelWithString: "")
    private let workspaceShortcutStack = NSStackView()
    private let windowShortcutStack = NSStackView()
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var configErrorNotice = WorkspaceSettingsControlFactory.configErrorNotice(label: configErrorLabel)

    init(
        store: AppSettingsStore,
        settingsService: any WorkspaceSettingsServing,
        shortcutRecordingController: ShortcutRecordingController,
        onChange: @escaping () -> Void
    ) {
        self.store = store
        self.settingsService = settingsService
        self.shortcutRecordingController = shortcutRecordingController
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))

        configure(
            windowSwitcherSizeSlider,
            action: #selector(windowSwitcherSizeChanged),
            width: 220,
            accessibilityIdentifier: "kkaci.settings.switcher.window-size"
        )
        configure(
            workspaceSwitcherSizeSlider,
            action: #selector(workspaceSwitcherSizeChanged),
            width: 220,
            accessibilityIdentifier: "kkaci.settings.switcher.workspace-size"
        )
        configureValueLabel(windowSwitcherSizeValueLabel)
        configureValueLabel(workspaceSwitcherSizeValueLabel)
        configureVerticalStack(workspaceShortcutStack, spacing: 0)
        configureVerticalStack(windowShortcutStack, spacing: 0)

        let header = SettingsControlFactory.header(
            title: "Switcher",
            symbolName: "rectangle.on.rectangle.fill"
        )
        let workspaceSection = makeSwitcherSection(
            title: "Workspace",
            shortcutStack: workspaceShortcutStack,
            sizeSlider: workspaceSwitcherSizeSlider,
            sizeValueLabel: workspaceSwitcherSizeValueLabel
        )
        let windowSection = makeSwitcherSection(
            title: "Window",
            shortcutStack: windowShortcutStack,
            sizeSlider: windowSwitcherSizeSlider,
            sizeValueLabel: windowSwitcherSizeValueLabel
        )
        let root = NSStackView(views: [
            header,
            configErrorNotice,
            workspaceSection,
            windowSection
        ])
        configureVerticalStack(root, spacing: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            configErrorNotice.widthAnchor.constraint(equalTo: root.widthAnchor),
            workspaceSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            windowSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded, shortcutRecordingController.cancel() else {
            return
        }

        let appSettings = store.snapshot()
        windowSwitcherSizeSlider.doubleValue = appSettings.windowSwitcherSize
        workspaceSwitcherSizeSlider.doubleValue = appSettings.workspaceSwitcherSize
        updateSizeLabels()

        let workspaceSettings = settingsService.snapshot()
        rebuildShortcutRows(workspaceSettings)
        updateEditingState(workspaceSettings)
    }
}

private extension SwitcherSettingsViewController {
    private func makeSwitcherSection(
        title: String,
        shortcutStack: NSStackView,
        sizeSlider: NSSlider,
        sizeValueLabel: NSTextField
    ) -> NSView {
        let content = NSStackView(views: [
            shortcutStack,
            SettingsControlFactory.separator(),
            SettingsControlFactory.padded(optionRow(
                title: "Switcher Size",
                control: sliderControl(sizeSlider, valueLabel: sizeValueLabel)
            ))
        ])
        configureVerticalStack(content, spacing: 0)
        for row in content.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }

        return SettingsControlFactory.titledSection(
            title: title,
            content: SettingsControlFactory.groupBox(content: content)
        )
    }

    private func rebuildShortcutRows(_ snapshot: WorkspaceSettingsSnapshot) {
        removeArrangedSubviews(from: workspaceShortcutStack)
        let workspaceRow = SettingsControlFactory.padded(
            WorkspaceSettingsControlFactory.switcherRow(
                title: "Cycle Keybinding",
                shortcut: snapshot.workspaceSwitcher,
                shortcutTarget: .workspaceSwitcher,
                validationMessages: snapshot.shortcutValidationMessages,
                action: (self, #selector(beginShortcutRecording(_:)))
            ),
            vertical: 10,
            horizontal: 14
        )
        workspaceShortcutStack.addArrangedSubview(workspaceRow)
        workspaceRow.widthAnchor.constraint(equalTo: workspaceShortcutStack.widthAnchor).isActive = true

        removeArrangedSubviews(from: windowShortcutStack)
        let windowRow = SettingsControlFactory.padded(
            WorkspaceSettingsControlFactory.switcherRow(
                title: "Cycle Keybinding",
                shortcut: snapshot.windowSwitcher,
                shortcutTarget: .windowSwitcher,
                validationMessages: snapshot.shortcutValidationMessages,
                action: (self, #selector(beginShortcutRecording(_:)))
            ),
            vertical: 10,
            horizontal: 14
        )
        windowShortcutStack.addArrangedSubview(windowRow)
        windowRow.widthAnchor.constraint(equalTo: windowShortcutStack.widthAnchor).isActive = true
    }

    private func updateEditingState(_ snapshot: WorkspaceSettingsSnapshot) {
        configErrorLabel.stringValue = snapshot.isEditable
            ? ""
            : "Configuration is invalid. Fix config.yaml in General before editing shortcuts."
        configErrorNotice.isHidden = snapshot.isEditable
        setControlsEnabled(snapshot.isEditable, in: workspaceShortcutStack)
        setControlsEnabled(snapshot.isEditable, in: windowShortcutStack)
    }

    private func setControlsEnabled(_ isEnabled: Bool, in view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = isEnabled
        }
        for subview in view.subviews {
            setControlsEnabled(isEnabled, in: subview)
        }
    }

    private func optionRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        let row = NSStackView(views: [titleLabel, SettingsControlFactory.flexibleSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func configure(
        _ slider: NSSlider,
        action: Selector,
        width: CGFloat,
        accessibilityIdentifier: String
    ) {
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        slider.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    private func configureValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.alignment = .right
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 46).isActive = true
    }

    private func sliderControl(_ slider: NSSlider, valueLabel: NSTextField) -> NSView {
        let control = NSStackView(views: [slider, valueLabel])
        control.orientation = .horizontal
        control.alignment = .centerY
        control.spacing = 10
        return control
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

    @objc private func beginShortcutRecording(_ sender: ShortcutRecorderButton) {
        shortcutRecordingController.begin(sender)
    }

    @objc private func windowSwitcherSizeChanged() {
        store.setWindowSwitcherSize(windowSwitcherSizeSlider.doubleValue)
        updateSizeLabels()
        onChange()
    }

    @objc private func workspaceSwitcherSizeChanged() {
        store.setWorkspaceSwitcherSize(workspaceSwitcherSizeSlider.doubleValue)
        updateSizeLabels()
        onChange()
    }

    private func updateSizeLabels() {
        windowSwitcherSizeValueLabel.stringValue = percentage(
            windowSwitcherSizeSlider.doubleValue,
            in: SwitcherSizeRange.window
        )
        workspaceSwitcherSizeValueLabel.stringValue = percentage(
            workspaceSwitcherSizeSlider.doubleValue,
            in: SwitcherSizeRange.workspace
        )
    }

    private func percentage(_ value: Double, in range: ClosedRange<Double>) -> String {
        let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return "\(Int((progress * 100).rounded()))%"
    }
}
