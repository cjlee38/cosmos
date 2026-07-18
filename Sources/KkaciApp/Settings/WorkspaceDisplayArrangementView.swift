import AppKit
import KkaciCore

final class WorkspaceDisplayArrangementView: NSView {
    private var displayCards: [(item: WorkspaceSettingsDisplay, view: WorkspaceDisplayCardView)] = []
    private let emptyLabel = NSTextField(labelWithString: "No displays detected")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func apply(_ displays: [WorkspaceSettingsDisplay]) {
        for displayCard in displayCards {
            displayCard.view.removeFromSuperview()
        }

        displayCards = displays.map { item in
            let card = WorkspaceDisplayCardView(item: item)
            addSubview(card)
            return (item, card)
        }
        emptyLabel.isHidden = !displayCards.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        emptyLabel.frame = bounds

        guard !displayCards.isEmpty else {
            return
        }

        let desktopBounds = displayCards
            .map(\.item.frame)
            .dropFirst()
            .reduce(displayCards[0].item.frame) { $0.union($1) }
        guard desktopBounds.width > 0, desktopBounds.height > 0 else {
            return
        }

        let availableBounds = bounds.insetBy(dx: 14, dy: 14)
        let scale = min(
            availableBounds.width / desktopBounds.width,
            availableBounds.height / desktopBounds.height
        )
        let renderedSize = NSSize(
            width: desktopBounds.width * scale,
            height: desktopBounds.height * scale
        )
        let renderedOrigin = NSPoint(
            x: availableBounds.midX - renderedSize.width / 2,
            y: availableBounds.midY - renderedSize.height / 2
        )

        for displayCard in displayCards {
            let frame = displayCard.item.frame
            displayCard.view.frame = NSRect(
                x: renderedOrigin.x + (frame.minX - desktopBounds.minX) * scale,
                y: renderedOrigin.y + (frame.minY - desktopBounds.minY) * scale,
                width: frame.width * scale,
                height: frame.height * scale
            ).integral
        }
    }
}

private final class WorkspaceDisplayCardView: NSView {
    private let workspaceFlow = WorkspacePillFlowView()

    init(item: WorkspaceSettingsDisplay) {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityIdentifier("kkaci.settings.display.\(item.monitorSlot)")

        let title = NSTextField(labelWithString: "\(item.monitorSlot) (\(item.name))")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail

        let roleName = switch item.role {
        case .main:
            "Main"
        case .extended:
            "Extended"
        }
        let role = NSTextField(labelWithString: roleName)
        role.font = .systemFont(ofSize: 10.5, weight: .medium)
        role.textColor = .secondaryLabelColor
        role.lineBreakMode = .byTruncatingTail

        let heading = NSStackView(views: [title, role])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 1
        heading.translatesAutoresizingMaskIntoConstraints = false

        workspaceFlow.translatesAutoresizingMaskIntoConstraints = false
        workspaceFlow.apply(item.workspaceIDs.map(\.rawValue))

        addSubview(heading)
        addSubview(workspaceFlow)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            workspaceFlow.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            workspaceFlow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            workspaceFlow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            workspaceFlow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
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
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 7
    }
}

private final class WorkspacePillFlowView: NSView {
    private var pills: [WorkspacePillView] = []
    private let emptyLabel = NSTextField(labelWithString: "No workspaces")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func apply(_ workspaceIDs: [String]) {
        for pill in pills {
            pill.removeFromSuperview()
        }
        pills = workspaceIDs.map { workspaceID in
            let pill = WorkspacePillView(title: workspaceID)
            addSubview(pill)
            return pill
        }
        emptyLabel.isHidden = !pills.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        emptyLabel.frame = bounds

        let spacing: CGFloat = 5
        var origin = NSPoint.zero
        var rowHeight: CGFloat = 0
        for pill in pills {
            let size = pill.intrinsicContentSize
            if origin.x > 0, origin.x + size.width > bounds.width {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            pill.isHidden = origin.y + size.height > bounds.height
            pill.frame = NSRect(origin: origin, size: size)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private final class WorkspacePillView: NSView {
    private let label: NSTextField

    init(title: String) {
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: min(label.intrinsicContentSize.width + 16, 100), height: 24)
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        layer?.cornerRadius = 6
    }
}
