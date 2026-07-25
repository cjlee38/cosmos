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
    private let appSettingsStore: AppSettingsStore
    private let appSettingsChanged: () -> Void
    private let runSetupHandler: () -> Void

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
    private let menuBarStyleControl = NSSegmentedControl(
        labels: MenuBarIconStyle.allCases.map(\.preview),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private var permissionControls: [SettingsPermission: PermissionControls] = [:]
    private var permissionByButtonID: [ObjectIdentifier: SettingsPermission] = [:]
    private var requestedPermissions: Set<SettingsPermission> = []

    init(
        service: GeneralSettingsService,
        configURLProvider: @escaping () -> URL?,
        configStatusProvider: @escaping () -> ConfigRuntimeStatus,
        reloadConfigHandler: @escaping () -> Void,
        appSettingsStore: AppSettingsStore,
        appSettingsChanged: @escaping () -> Void,
        runSetupHandler: @escaping () -> Void
    ) {
        self.service = service
        self.configURLProvider = configURLProvider
        self.configStatusProvider = configStatusProvider
        self.reloadConfigHandler = reloadConfigHandler
        self.appSettingsStore = appSettingsStore
        self.appSettingsChanged = appSettingsChanged
        self.runSetupHandler = runSetupHandler
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))

        let (scrollView, documentView) = makeScrollView()
        view.addSubview(scrollView)

        let root = NSStackView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20

        let header = SettingsControlFactory.header(title: "General", symbolName: "gearshape.fill")
        let launchSection = makeLaunchAtLoginSection()
        let menuBarSection = makeMenuBarSection()
        let configurationSection = makeConfigurationSection()
        let permissionsSection = makePermissionsSection()
        let setupSection = makeSetupSection()
        root.addArrangedSubview(header)
        root.addArrangedSubview(launchSection)
        root.addArrangedSubview(menuBarSection)
        root.addArrangedSubview(configurationSection)
        root.addArrangedSubview(permissionsSection)
        root.addArrangedSubview(setupSection)
        documentView.addSubview(root)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            root.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -26),
            root.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            launchSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            menuBarSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            permissionsSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            configurationSection.widthAnchor.constraint(equalTo: root.widthAnchor),
            setupSection.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }

        let snapshot = service.snapshot()
        updateLaunchAtLogin(snapshot.launchAtLoginStatus)
        updateMenuBarStyle()
        updatePermissions(snapshot.permissions)
        updateConfiguration()
    }
}

private extension GeneralSettingsViewController {
    private func makeScrollView() -> (scrollView: NSScrollView, documentView: NSView) {
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

    private func makeMenuBarSection() -> NSView {
        menuBarStyleControl.segmentStyle = .rounded
        menuBarStyleControl.target = self
        menuBarStyleControl.action = #selector(menuBarStyleChanged)
        menuBarStyleControl.translatesAutoresizingMaskIntoConstraints = false
        menuBarStyleControl.widthAnchor.constraint(equalToConstant: 260).isActive = true
        menuBarStyleControl.setAccessibilityIdentifier("cosmos.settings.general.menu-bar-style")

        let title = NSTextField(labelWithString: "Icon Style")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let row = NSStackView(views: [
            title,
            SettingsControlFactory.flexibleSpacer(),
            menuBarStyleControl
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return SettingsControlFactory.titledSection(
            title: "Menu Bar",
            content: SettingsControlFactory.groupBox(
                content: SettingsControlFactory.padded(row)
            )
        )
    }

    private func makeLaunchAtLoginSection() -> NSView {
        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(launchAtLoginChanged)

        launchAtLoginStatusLabel.textColor = .secondaryLabelColor
        launchAtLoginSettingsButton.target = self
        launchAtLoginSettingsButton.action = #selector(openLoginItemsSettings)

        let title = NSTextField(labelWithString: "Launch at Login")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let spacer = SettingsControlFactory.flexibleSpacer()
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

    private func makeSetupSection() -> NSView {
        let title = NSTextField(labelWithString: "Setup Assistant")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let detail = NSTextField(labelWithString: "Review permissions, displays, and spaces.")
        detail.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3

        let button = NSButton(title: "Run Setup Again...", target: self, action: #selector(runSetupAgain))
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

        return SettingsControlFactory.titledSection(
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

        let row = NSStackView(views: [
            title,
            SettingsControlFactory.flexibleSpacer(),
            statusIcon,
            statusLabel,
            settingsButton
        ])
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

        configureConfigStatusIcon()
        configErrorLabel.textColor = .systemRed
        configErrorLabel.font = .systemFont(ofSize: 12)
        configErrorLabel.maximumNumberOfLines = 2

        let fileRow = makeConfigFileRow()
        let details = NSStackView(views: [fileRow, configErrorLabel])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 10
        fileRow.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true

        let buttons = SettingsControlFactory.filledButtonRow(
            actions: [
                (openConfigButton, #selector(openConfig)),
                (revealConfigButton, #selector(revealConfig)),
                (reloadConfigButton, #selector(reloadConfig))
            ],
            target: self
        )

        return SettingsControlFactory.titledSection(
            title: "Configuration",
            content: SettingsControlFactory.actionGroup(details: details, actions: buttons)
        )
    }

    private func makeConfigFileRow() -> NSView {
        let fileIcon = NSImageView()
        fileIcon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Config file")
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        fileIcon.contentTintColor = .secondaryLabelColor
        fileIcon.translatesAutoresizingMaskIntoConstraints = false
        fileIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        fileIcon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let fileName = NSTextField(labelWithString: "config.yaml")
        fileName.font = .systemFont(ofSize: 14, weight: .semibold)
        let fileDetails = NSStackView(views: [fileName, configPathLabel])
        fileDetails.orientation = .vertical
        fileDetails.alignment = .leading
        fileDetails.spacing = 2

        let status = NSStackView(views: [configStatusIcon, configStatusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 5

        let fileRow = NSStackView(views: [
            fileIcon,
            fileDetails,
            SettingsControlFactory.flexibleSpacer(),
            status
        ])
        fileRow.orientation = .horizontal
        fileRow.alignment = .centerY
        fileRow.spacing = 10
        return fileRow
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
}

private extension GeneralSettingsViewController {
    private func updateMenuBarStyle() {
        let style = appSettingsStore.snapshot().menuBarIconStyle
        menuBarStyleControl.selectedSegment = MenuBarIconStyle.allCases.firstIndex(of: style) ?? 0
    }

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
            controls.settingsButton.title = requestedPermissions.contains(status.permission)
                ? "Open System Settings"
                : "Request Permission"
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
            updateConfigStatus(symbol: "checkmark.circle.fill", title: "Valid", color: .systemGreen)
        case let .invalid(error):
            updateConfigStatus(symbol: "xmark.circle.fill", title: "Invalid", color: .systemRed, error: error)
        case let .runtimeError(error):
            updateConfigStatus(
                symbol: "exclamationmark.triangle.fill",
                title: "Error",
                color: .systemOrange,
                error: error
            )
        }
    }

    private func updateConfigStatus(symbol: String, title: String, color: NSColor, error: String? = nil) {
        configStatusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        configStatusIcon.contentTintColor = color
        configStatusLabel.stringValue = title
        configStatusLabel.textColor = color
        configErrorLabel.stringValue = error ?? ""
        configErrorLabel.isHidden = error == nil
    }

    @objc private func launchAtLoginChanged() {
        do {
            try service.setLaunchAtLoginEnabled(launchAtLoginSwitch.state == .on)
        } catch {
            NSApp.presentError(error)
        }
        refresh()
    }

    @objc private func menuBarStyleChanged() {
        let styles = MenuBarIconStyle.allCases
        guard styles.indices.contains(menuBarStyleControl.selectedSegment) else {
            return
        }
        appSettingsStore.setMenuBarIconStyle(styles[menuBarStyleControl.selectedSegment])
        appSettingsChanged()
    }

    @objc private func openLoginItemsSettings() {
        service.openLoginItemsSettings()
    }

    @objc private func openPermissionSettings(_ sender: NSButton) {
        guard let permission = permissionByButtonID[ObjectIdentifier(sender)] else {
            return
        }
        if requestedPermissions.contains(permission) {
            service.openSystemSettings(for: permission)
        } else {
            requestedPermissions.insert(permission)
            service.requestPermission(permission)
            refresh()
        }
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

    @objc private func runSetupAgain() {
        runSetupHandler()
    }
}
