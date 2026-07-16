import AppKit

final class GeneralSettingsViewController: NSViewController {
    private struct PermissionControls {
        let statusIcon: NSImageView
        let statusLabel: NSTextField
        let settingsButton: NSButton
    }

    private let service: GeneralSettingsService
    private let configURLProvider: () -> URL?
    private let configStatusProvider: () -> ConfigRuntimeStatus
    private let reloadConfigHandler: () -> Void

    private let launchAtLoginSwitch = NSSwitch()
    private let launchAtLoginStatusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginSettingsButton = NSButton(
        title: "Open System Settings",
        target: nil,
        action: nil
    )
    private let configPathLabel = NSTextField(labelWithString: "")
    private let configStatusIcon = NSImageView()
    private let configStatusLabel = NSTextField(labelWithString: "")
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private let openConfigButton = SettingsFilledButton(title: "Open in Editor")
    private let revealConfigButton = SettingsFilledButton(title: "Reveal in Finder")
    private let reloadConfigButton = SettingsFilledButton(title: "Reload from Disk")
    private var permissionControls: [SettingsPermission: PermissionControls] = [:]
    private var permissionByButtonID: [ObjectIdentifier: SettingsPermission] = [:]

    init(
        service: GeneralSettingsService,
        configURLProvider: @escaping () -> URL?,
        configStatusProvider: @escaping () -> ConfigRuntimeStatus,
        reloadConfigHandler: @escaping () -> Void
    ) {
        self.service = service
        self.configURLProvider = configURLProvider
        self.configStatusProvider = configStatusProvider
        self.reloadConfigHandler = reloadConfigHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20

        let header = makeHeader()
        let launchSection = makeLaunchAtLoginSection()
        let configurationSection = makeConfigurationSection()
        let permissionsSection = makePermissionsSection()
        root.addArrangedSubview(header)
        root.addArrangedSubview(launchSection)
        root.addArrangedSubview(configurationSection)
        root.addArrangedSubview(permissionsSection)
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            launchSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            permissionsSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            configurationSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }

        let snapshot = service.snapshot()
        updateLaunchAtLogin(snapshot.launchAtLoginStatus)
        updatePermissions(snapshot.permissions)
        updateConfiguration()
    }
}

private extension GeneralSettingsViewController {
    private func makeHeader() -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "General")
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let title = NSTextField(labelWithString: "General")
        title.font = .systemFont(ofSize: 22, weight: .bold)

        let header = NSStackView(views: [icon, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        return header
    }

    private func makeLaunchAtLoginSection() -> NSView {
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)

        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        launchAtLoginSettingsButton.target = self
        launchAtLoginSettingsButton.action = #selector(openLoginItemsSettings)

        let title = NSTextField(labelWithString: "Launch at Login")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let spacer = flexibleSpacer()
        let row = NSStackView(views: [
            title,
            spacer,
            launchAtLoginStatusLabel,
            launchAtLoginSettingsButton,
            launchAtLoginSwitch
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return SettingsControlFactory.groupBox(
            content: SettingsControlFactory.padded(row)
        )
    }

    private func makePermissionsSection() -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0

        for (index, permission) in SettingsPermission.allCases.enumerated() {
            if index > 0 {
                let divider = SettingsControlFactory.separator()
                rows.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
            }
            let row = makePermissionRow(permission)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }

        return titledSection(
            title: "Permissions",
            content: SettingsControlFactory.groupBox(content: rows)
        )
    }

    private func makePermissionRow(_ permission: SettingsPermission) -> NSView {
        let title = NSTextField(labelWithString: permission.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)

        let statusIcon = NSImageView()
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor

        let settingsButton = NSButton(
            title: "Open System Settings",
            target: self,
            action: #selector(openPermissionSettings(_:))
        )
        permissionByButtonID[ObjectIdentifier(settingsButton)] = permission
        permissionControls[permission] = PermissionControls(
            statusIcon: statusIcon,
            statusLabel: statusLabel,
            settingsButton: settingsButton
        )

        let row = NSStackView(views: [title, flexibleSpacer(), statusIcon, statusLabel, settingsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return SettingsControlFactory.padded(row)
    }

    private func makeConfigurationSection() -> NSView {
        configureReloadConfigButton()

        configPathLabel.isSelectable = true
        configPathLabel.textColor = .secondaryLabelColor
        configPathLabel.lineBreakMode = .byTruncatingMiddle
        configPathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let fileIcon = NSImageView()
        fileIcon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Config file")
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        fileIcon.contentTintColor = .secondaryLabelColor
        fileIcon.translatesAutoresizingMaskIntoConstraints = false
        fileIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        fileIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let fileName = NSTextField(labelWithString: "config.toml")
        fileName.font = .systemFont(ofSize: 14, weight: .semibold)
        let fileDetails = NSStackView(views: [fileName, configPathLabel])
        fileDetails.orientation = .vertical
        fileDetails.alignment = .leading
        fileDetails.spacing = 2

        configureConfigStatusIcon()

        let status = NSStackView(views: [configStatusIcon, configStatusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 5

        let fileRow = NSStackView(views: [fileIcon, fileDetails, flexibleSpacer(), status])
        fileRow.orientation = .horizontal
        fileRow.alignment = .centerY
        fileRow.spacing = 10

        configErrorLabel.textColor = .systemRed
        configErrorLabel.font = .systemFont(ofSize: 12)
        configErrorLabel.maximumNumberOfLines = 2

        let buttons = SettingsControlFactory.filledButtonRow(
            actions: [
                (openConfigButton, #selector(openConfig)),
                (revealConfigButton, #selector(revealConfig)),
                (reloadConfigButton, #selector(reloadConfig))
            ],
            target: self
        )

        let details = NSStackView(views: [fileRow, configErrorLabel])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 10
        fileRow.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true

        return titledSection(
            title: "Configuration",
            content: SettingsControlFactory.actionGroup(details: details, actions: buttons)
        )
    }

    private func configureReloadConfigButton() {
        reloadConfigButton.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Reload"
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
        reloadConfigButton.imagePosition = .imageLeading
        reloadConfigButton.imageHugsTitle = true
    }

    private func configureConfigStatusIcon() {
        configStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        configStatusIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        configStatusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        configStatusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        configStatusLabel.font = .systemFont(ofSize: 13, weight: .medium)
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

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }
}

private extension GeneralSettingsViewController {
    private func updateLaunchAtLogin(_ status: LaunchAtLoginStatus) {
        launchAtLoginSwitch.state = status == .enabled ? .on : .off
        launchAtLoginSettingsButton.isHidden = status != .requiresApproval

        switch status {
        case .disabled, .enabled:
            launchAtLoginSwitch.isEnabled = true
            launchAtLoginStatusLabel.stringValue = ""
        case .requiresApproval:
            launchAtLoginSwitch.isEnabled = false
            launchAtLoginStatusLabel.stringValue = "Approval required"
        }
    }

    private func updatePermissions(_ statuses: [SettingsPermissionStatus]) {
        for status in statuses {
            guard let controls = permissionControls[status.permission] else {
                continue
            }
            let symbolName = status.isGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
            controls.statusIcon.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: status.isGranted ? "Allowed" : "Not allowed"
            )
            controls.statusIcon.contentTintColor = status.isGranted ? .systemGreen : .systemRed
            controls.statusLabel.stringValue = status.isGranted ? "Allowed" : "Not allowed"
            controls.settingsButton.isHidden = status.isGranted
        }
    }

    private func updateConfiguration() {
        let configURL = configURLProvider()
        configPathLabel.stringValue = configURL?.path ?? "Config file unavailable"
        configPathLabel.toolTip = configURL?.path
        openConfigButton.isEnabled = configURL != nil
        revealConfigButton.isEnabled = configURL != nil

        switch configStatusProvider() {
        case .valid:
            configStatusIcon.image = NSImage(
                systemSymbolName: "checkmark.circle.fill",
                accessibilityDescription: "Valid"
            )
            configStatusIcon.contentTintColor = .systemGreen
            configStatusLabel.stringValue = "Valid"
            configStatusLabel.textColor = .systemGreen
            configErrorLabel.stringValue = ""
            configErrorLabel.isHidden = true
        case let .invalid(error):
            configStatusIcon.image = NSImage(
                systemSymbolName: "xmark.circle.fill",
                accessibilityDescription: "Invalid"
            )
            configStatusIcon.contentTintColor = .systemRed
            configStatusLabel.stringValue = "Invalid"
            configStatusLabel.textColor = .systemRed
            configErrorLabel.stringValue = error
            configErrorLabel.isHidden = false
        }
    }

    @objc private func launchAtLoginChanged() {
        do {
            try service.setLaunchAtLoginEnabled(launchAtLoginSwitch.state == .on)
        } catch {
            NSApp.presentError(error)
        }
        refresh()
    }

    @objc private func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    @objc private func openPermissionSettings(_ sender: NSButton) {
        guard let permission = permissionByButtonID[ObjectIdentifier(sender)] else {
            return
        }
        service.openSystemSettings(for: permission)
    }

    @objc private func openConfig() {
        guard let url = configURLProvider() else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealConfig() {
        guard let url = configURLProvider() else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func reloadConfig() {
        reloadConfigHandler()
        refresh()
    }
}
