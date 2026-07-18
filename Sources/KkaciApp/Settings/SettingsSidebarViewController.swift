import AppKit

final class SettingsSidebarViewController: NSViewController {
    var onSelectionChanged: ((SettingsSection) -> Bool)?

    private let sections = SettingsSection.allCases
    private var buttons: [SettingsSection: SettingsSidebarButton] = [:]

    override func loadView() {
        let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 190, height: 540))
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        view = sidebar

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4

        for (index, section) in sections.enumerated() {
            let button = SettingsSidebarButton(section: section)
            button.tag = index
            button.target = self
            button.action = #selector(sectionSelected(_:))
            buttons[section] = button
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 52),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8)
        ])
    }

    func select(_ section: SettingsSection) {
        _ = view
        for (candidate, button) in buttons {
            button.isSelected = candidate == section
        }
    }

    @objc private func sectionSelected(_ sender: NSButton) {
        guard sections.indices.contains(sender.tag) else {
            return
        }
        let section = sections[sender.tag]
        guard onSelectionChanged?(section) != false else {
            return
        }
        select(section)
    }
}

private final class SettingsSidebarButton: NSButton {
    var isSelected = false {
        didSet {
            needsDisplay = true
        }
    }

    init(section: SettingsSection) {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        setButtonType(.momentaryPushIn)

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage(
            systemSymbolName: section.symbolName,
            accessibilityDescription: section.title
        )
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        icon.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: section.title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.lineBreakMode = .byTruncatingTail

        addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = isSelected
            ? NSColor.unemphasizedSelectedContentBackgroundColor.cgColor
            : NSColor.clear.cgColor
        layer?.cornerRadius = 7
    }
}
