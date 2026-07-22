import AppKit
import KkaciCore

final class WindowSettingsViewController: NSViewController {
    private let settingsService: any WorkspaceSettingsServing
    private let shortcutRecordingController: ShortcutRecordingController
    private let shortcutStack = NSStackView()
    private let configErrorLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var configErrorNotice = WorkspaceSettingsControlFactory.configErrorNotice(label: configErrorLabel)

    init(
        settingsService: any WorkspaceSettingsServing,
        shortcutRecordingController: ShortcutRecordingController
    ) {
        self.settingsService = settingsService
        self.shortcutRecordingController = shortcutRecordingController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 540))
        shortcutStack.orientation = .vertical
        shortcutStack.alignment = .leading
        shortcutStack.spacing = 0

        let header = SettingsControlFactory.header(title: "Window", symbolName: "macwindow")
        let section = SettingsControlFactory.titledSection(
            title: "Position",
            content: SettingsControlFactory.groupBox(content: shortcutStack)
        )
        let root = NSStackView(views: [header, configErrorNotice, section])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
            configErrorNotice.widthAnchor.constraint(equalTo: root.widthAnchor),
            section.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])
        refresh()
    }

    func refresh() {
        guard isViewLoaded, shortcutRecordingController.cancel() else {
            return
        }
        let snapshot = settingsService.snapshot()
        rebuildShortcutRow(snapshot)
        setControlsEnabled(snapshot.isEditable, in: shortcutStack)
        configErrorLabel.stringValue = snapshot.isEditable
            ? ""
            : "Fix config.yaml before editing window shortcuts."
        configErrorNotice.isHidden = snapshot.isEditable
    }

    private func rebuildShortcutRow(_ snapshot: WorkspaceSettingsSnapshot) {
        for view in shortcutStack.arrangedSubviews {
            shortcutStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let row = SettingsControlFactory.padded(
            WorkspaceSettingsControlFactory.switcherRow(
                title: "Center Window",
                shortcut: snapshot.centerWindow,
                shortcutTarget: .centerWindow,
                validationMessages: snapshot.shortcutValidationMessages,
                action: (self, #selector(beginShortcutRecording(_:)))
            ),
            vertical: 10,
            horizontal: 14
        )
        shortcutStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: shortcutStack.widthAnchor).isActive = true
    }

    @objc private func beginShortcutRecording(_ sender: ShortcutRecorderButton) {
        shortcutRecordingController.begin(sender)
    }

    private func setControlsEnabled(_ isEnabled: Bool, in view: NSView) {
        if let control = view as? NSControl {
            control.isEnabled = isEnabled
        }
        for subview in view.subviews {
            setControlsEnabled(isEnabled, in: subview)
        }
    }
}
