import AppKit

enum GeneralSettingsViewFactory {
    static func makeScrollView() -> (scrollView: NSScrollView, documentView: NSView) {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        let documentView = SettingsDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        return (scrollView, documentView)
    }

    static func makeMenuBarSection(
        control: NSSegmentedControl,
        target: AnyObject,
        action: Selector
    ) -> NSView {
        control.segmentStyle = .rounded
        control.target = target
        control.action = action
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 260).isActive = true
        control.setAccessibilityIdentifier("cosmos.settings.general.menu-bar-style")

        let title = NSTextField(labelWithString: "Icon Style")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let row = NSStackView(views: [title, SettingsControlFactory.flexibleSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return SettingsControlFactory.titledSection(
            title: "Menu Bar",
            content: SettingsControlFactory.groupBox(content: SettingsControlFactory.padded(row))
        )
    }

    static func makeLaunchAtLoginSection(
        toggle: NSSwitch,
        statusLabel: NSTextField,
        settingsButton: NSButton,
        target: AnyObject,
        actions: (toggle: Selector, settings: Selector)
    ) -> NSView {
        toggle.target = target
        toggle.action = actions.toggle
        statusLabel.textColor = .secondaryLabelColor
        settingsButton.target = target
        settingsButton.action = actions.settings

        let title = NSTextField(labelWithString: "Launch at Login")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let row = NSStackView(views: [
            title,
            SettingsControlFactory.flexibleSpacer(),
            statusLabel,
            settingsButton,
            toggle
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return SettingsControlFactory.groupBox(content: SettingsControlFactory.padded(row))
    }

    static func makeSetupSection(target: AnyObject, action: Selector) -> NSView {
        let title = NSTextField(labelWithString: "Setup Assistant")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let detail = NSTextField(labelWithString: "Review permissions, displays, and spaces.")
        detail.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let button = NSButton(title: "Run Setup Again...", target: target, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setAccessibilityIdentifier("cosmos.settings.general.run-setup")
        let row = NSStackView(views: [labels, SettingsControlFactory.flexibleSpacer(), button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return SettingsControlFactory.titledSection(
            title: "Setup",
            content: SettingsControlFactory.groupBox(content: SettingsControlFactory.padded(row))
        )
    }

    static func makeConfigFileRow(
        pathLabel: NSTextField,
        statusIcon: NSImageView,
        statusLabel: NSTextField
    ) -> NSView {
        let fileIcon = NSImageView()
        fileIcon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Config file")
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        fileIcon.contentTintColor = .secondaryLabelColor
        fileIcon.translatesAutoresizingMaskIntoConstraints = false
        fileIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        fileIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let fileName = NSTextField(labelWithString: "config.yaml")
        fileName.font = .systemFont(ofSize: 14, weight: .semibold)
        let fileDetails = NSStackView(views: [fileName, pathLabel])
        fileDetails.orientation = .vertical
        fileDetails.alignment = .leading
        fileDetails.spacing = 2
        let status = NSStackView(views: [statusIcon, statusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 5

        let row = NSStackView(views: [
            fileIcon,
            fileDetails,
            SettingsControlFactory.flexibleSpacer(),
            status
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    static func constrainContent(
        in view: NSView,
        scrollView: NSScrollView,
        documentView: NSView,
        root: NSStackView,
        sections: [NSView]
    ) {
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
        for section in sections {
            section.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
    }
}
