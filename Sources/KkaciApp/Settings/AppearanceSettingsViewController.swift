import AppKit

final class AppearanceSettingsViewController: NSViewController {
    private let store: AppSettingsStore
    private let onChange: () -> Void
    private let menuBarStyleControl = NSSegmentedControl(
        labels: MenuBarIconStyle.allCases.map(\.preview),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
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

    init(store: AppSettingsStore, onChange: @escaping () -> Void) {
        self.store = store
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
            menuBarStyleControl,
            action: #selector(menuBarStyleChanged),
            width: 260
        )
        configure(
            windowSwitcherSizeSlider,
            action: #selector(windowSwitcherSizeChanged),
            width: 220
        )
        configure(
            workspaceSwitcherSizeSlider,
            action: #selector(workspaceSwitcherSizeChanged),
            width: 220
        )
        configureValueLabel(windowSwitcherSizeValueLabel)
        configureValueLabel(workspaceSwitcherSizeValueLabel)

        let header = makeHeader()
        let menuBarSection = makeMenuBarSection()
        let switcherSection = makeSwitcherSection()
        let root = NSStackView(views: [header, menuBarSection, switcherSection])
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            menuBarSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            switcherSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }

        let snapshot = store.snapshot()
        menuBarStyleControl.selectedSegment = MenuBarIconStyle.allCases.firstIndex(
            of: snapshot.menuBarIconStyle
        ) ?? 0
        windowSwitcherSizeSlider.doubleValue = snapshot.windowSwitcherSize
        workspaceSwitcherSizeSlider.doubleValue = snapshot.workspaceSwitcherSize
        updateSizeLabels()
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "paintbrush.fill", accessibilityDescription: "Appearance")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let title = NSTextField(labelWithString: "Appearance")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let header = NSStackView(views: [icon, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        return header
    }

    private func makeMenuBarSection() -> NSView {
        titledSection(
            title: "Menu Bar",
            content: SettingsControlFactory.groupBox(
                content: SettingsControlFactory.padded(
                    optionRow(title: "Icon Style", control: menuBarStyleControl)
                )
            )
        )
    }

    private func makeSwitcherSection() -> NSView {
        let divider = SettingsControlFactory.separator()
        let rows = NSStackView(views: [
            SettingsControlFactory.padded(
                optionRow(
                    title: "Window Switcher",
                    control: sliderControl(
                        windowSwitcherSizeSlider,
                        valueLabel: windowSwitcherSizeValueLabel
                    )
                )
            ),
            divider,
            SettingsControlFactory.padded(
                optionRow(
                    title: "Workspace Switcher",
                    control: sliderControl(
                        workspaceSwitcherSizeSlider,
                        valueLabel: workspaceSwitcherSizeValueLabel
                    )
                )
            )
        ])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        for row in rows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        return titledSection(
            title: "Switcher Size",
            content: SettingsControlFactory.groupBox(content: rows)
        )
    }

    private func optionRow(title: String, control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        let row = NSStackView(views: [titleLabel, flexibleSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func titledSection(title: String, content: NSView) -> NSView {
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

    private func configure(_ control: NSSegmentedControl, action: Selector, width: CGFloat) {
        control.segmentStyle = .rounded
        control.target = self
        control.action = action
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func configure(_ slider: NSSlider, action: Selector, width: CGFloat) {
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
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

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    @objc private func menuBarStyleChanged() {
        let styles = MenuBarIconStyle.allCases
        guard styles.indices.contains(menuBarStyleControl.selectedSegment) else {
            return
        }
        store.setMenuBarIconStyle(styles[menuBarStyleControl.selectedSegment])
        onChange()
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
