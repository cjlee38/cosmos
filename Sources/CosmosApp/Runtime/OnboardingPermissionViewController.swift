import AppKit

final class OnboardingPermissionViewController: NSViewController {
    private struct PermissionControls {
        let statusIcon: NSImageView
        let statusLabel: NSTextField
        let actionButton: NSButton
    }

    private let service: GeneralSettingsService
    private var controls: [SettingsPermission: PermissionControls] = [:]
    private var permissionByButtonID: [ObjectIdentifier: SettingsPermission] = [:]
    private var requestedPermissions: Set<SettingsPermission> = []
    private var grantedPermissions: Set<SettingsPermission> = []

    var hasAccessibilityPermission: Bool {
        grantedPermissions.contains(.accessibility)
    }

    var hasScreenRecordingPermission: Bool {
        grantedPermissions.contains(.screenRecording)
    }

    init(service: GeneralSettingsService) {
        self.service = service
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 812, height: 560))

        let header = SettingsControlFactory.header(
            title: "Permissions",
            symbolName: "hand.raised.fill"
        )
        let description = makeDescription()
        let rows = makePermissionRows()
        let root = NSStackView(views: [header, description, rows])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            description.widthAnchor.constraint(equalTo: root.widthAnchor),
            rows.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        refresh()
    }

    func refresh() {
        guard isViewLoaded else {
            return
        }
        let statuses = service.snapshot().permissions
        grantedPermissions = Set(statuses.filter(\.isGranted).map(\.permission))
        for status in statuses {
            update(status)
        }
    }

    private func makeDescription() -> NSTextField {
        let description = NSTextField(wrappingLabelWithString:
            "Cosmos needs Accessibility to manage windows. Screen Recording is optional and enables previews.")
        description.textColor = .secondaryLabelColor
        description.font = .systemFont(ofSize: 13)
        return description
    }

    private func makePermissionRows() -> NSStackView {
        let rows = NSStackView(views: SettingsPermission.allCases.map(makePermissionRow))
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 12
        for row in rows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        return rows
    }

    private func makePermissionRow(_ permission: SettingsPermission) -> NSView {
        let icon = makePermissionIcon(permission)
        let labels = makePermissionLabels(permission)
        let permissionControls = makePermissionControls(permission)
        controls[permission] = permissionControls

        let row = NSStackView(views: [
            icon,
            labels,
            SettingsControlFactory.flexibleSpacer(),
            permissionControls.statusIcon,
            permissionControls.statusLabel,
            permissionControls.actionButton
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return SettingsControlFactory.groupBox(
            content: SettingsControlFactory.padded(row, vertical: 16, horizontal: 16)
        )
    }

    private func makePermissionIcon(_ permission: SettingsPermission) -> NSImageView {
        let icon = NSImageView()
        icon.image = NSImage(
            systemSymbolName: permission.symbolName,
            accessibilityDescription: permission.title
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return icon
    }

    private func makePermissionLabels(_ permission: SettingsPermission) -> NSStackView {
        let title = NSTextField(labelWithString: permission.title)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let detail = NSTextField(labelWithString: permission.onboardingDescription)
        detail.font = .systemFont(ofSize: 12.5)
        detail.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        return labels
    }

    private func makePermissionControls(_ permission: SettingsPermission) -> PermissionControls {
        let statusIcon = NSImageView()
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.widthAnchor.constraint(equalToConstant: 18).isActive = true
        statusIcon.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        let actionButton = NSButton(
            title: "Request Access",
            target: self,
            action: #selector(handlePermissionAction(_:))
        )
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .regular
        actionButton.setAccessibilityIdentifier("cosmos.onboarding.permission.\(permission.identifier)")
        permissionByButtonID[ObjectIdentifier(actionButton)] = permission
        return PermissionControls(
            statusIcon: statusIcon,
            statusLabel: statusLabel,
            actionButton: actionButton
        )
    }

    private func update(_ status: SettingsPermissionStatus) {
        guard let controls = controls[status.permission] else {
            return
        }
        controls.statusIcon.image = NSImage(
            systemSymbolName: status.isGranted ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: status.isGranted ? "Allowed" : "Not allowed"
        )
        controls.statusIcon.contentTintColor = status.isGranted ? .systemGreen : .secondaryLabelColor
        controls.statusLabel.stringValue = status.isGranted
            ? "Allowed"
            : status.permission == .accessibility ? "Required" : "Optional"
        controls.statusLabel.textColor = status.isGranted ? .systemGreen : .secondaryLabelColor
        controls.actionButton.isHidden = status.isGranted
        controls.actionButton.title = requestedPermissions.contains(status.permission)
            ? "Open System Settings"
            : "Request Access"
    }

    @objc private func handlePermissionAction(_ sender: NSButton) {
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
}

private extension SettingsPermission {
    var identifier: String {
        switch self {
        case .accessibility:
            "accessibility"
        case .screenRecording:
            "screen-recording"
        }
    }

    var symbolName: String {
        switch self {
        case .accessibility:
            "macwindow"
        case .screenRecording:
            "rectangle.inset.filled.and.person.filled"
        }
    }

    var onboardingDescription: String {
        switch self {
        case .accessibility:
            "Required to discover, move, and focus windows."
        case .screenRecording:
            "Optional. Enables live thumbnails in window and space switchers."
        }
    }
}
