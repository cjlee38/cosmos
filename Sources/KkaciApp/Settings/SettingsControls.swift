import AppKit

enum SettingsControlFactory {
    static func header(title: String, symbolName: String) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)

        let header = NSStackView(views: [icon, titleLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        return header
    }

    static func titledSection(title: String, content: NSView) -> NSView {
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

    static func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    static func filledButtonRow(
        actions: [(button: NSButton, action: Selector)],
        target: AnyObject
    ) -> NSStackView {
        for (button, action) in actions {
            button.target = target
            button.action = action
            button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let row = NSStackView(views: actions.map(\.button))
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fillEqually
        row.spacing = 8
        return row
    }

    static func actionGroup(details: NSView, actions: NSView) -> NSView {
        let detailsContainer = padded(details)
        let divider = separator()
        let actionsContainer = padded(actions, vertical: 6, horizontal: 6)
        let content = NSStackView(views: [detailsContainer, divider, actionsContainer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 0
        for arrangedView in content.arrangedSubviews {
            arrangedView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        return groupBox(content: content)
    }

    static func groupBox(content: NSView) -> NSView {
        SettingsGroupView(content: content)
    }

    static func padded(
        _ content: NSView,
        vertical: CGFloat = 12,
        horizontal: CGFloat = 14
    ) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: vertical),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontal),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontal),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -vertical)
        ])
        return container
    }

    static func separator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
}

private final class SettingsGroupView: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        wantsLayer = true

        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 8
    }
}

final class SettingsFilledButton: NSButton {
    private var isPressed = false

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        font = .systemFont(ofSize: 14, weight: .semibold)
        contentTintColor = .labelColor
        setButtonType(.momentaryPushIn)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = backgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 7
        layer?.opacity = isEnabled ? 1 : 0.45
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateLayer()
        super.mouseDown(with: event)
        isPressed = false
        updateLayer()
    }

    private var backgroundColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isDark {
            return NSColor(white: isPressed ? 0.27 : 0.20, alpha: 1)
        }
        return NSColor(white: isPressed ? 0.78 : 0.88, alpha: 1)
    }
}
