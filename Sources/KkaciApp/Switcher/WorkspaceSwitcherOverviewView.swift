import AppKit

struct WorkspaceSwitcherInteractions {
    let onHover: (String) -> Void
    let onClick: (String) -> Void
}

final class WorkspaceSwitcherListView: NSView {
    private var cardViewsByID: [String: WorkspacePreviewCardView] = [:]
    private var recycledCardViews: [WorkspacePreviewCardView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func ensureCapacity(_ count: Int) {
        let missingCount = max(0, count - cardViewsByID.count - recycledCardViews.count)
        for _ in 0 ..< missingCount {
            recycledCardViews.append(WorkspacePreviewCardView(frame: .zero))
        }
    }

    func configure(
        groups: [WorkspaceSwitcherGroup],
        selectedID: String,
        availableFrame: NSRect,
        size: CGFloat,
        interactions: WorkspaceSwitcherInteractions
    ) {
        let layout = WorkspaceOverviewLayout(
            groupCount: groups.count,
            availableFrame: availableFrame,
            size: size
        )
        frame = NSRect(origin: .zero, size: layout.contentSize)
        recycleMissingCards(keeping: Set(groups.map(\.id)))
        ensureCapacity(groups.count)

        let hoverGate = SwitcherHoverGate()
        for (index, group) in groups.enumerated() {
            let row = index / layout.columns
            let column = index % layout.columns
            let cell = layout.cellFrame(row: row, column: column)
            let card = cardView(for: group.id)
            card.configure(WorkspaceCardConfiguration(
                group: group,
                isSelected: group.id == selectedID,
                cardSize: layout.cardSize,
                hoverGate: hoverGate,
                onHover: interactions.onHover,
                onClick: interactions.onClick
            ))
            card.frame.origin = NSPoint(
                x: cell.midX - layout.cardSize.width / 2,
                y: cell.midY - layout.cardSize.height / 2
            )
        }
    }

    func updatePreviews(groups: [WorkspaceSwitcherGroup]) {
        for group in groups {
            cardViewsByID[group.id]?.update(group: group)
        }
    }

    func updateSelection(selectedID: String) {
        for (id, card) in cardViewsByID {
            card.updateSelection(id == selectedID)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for card in cardViewsByID.values.reversed() {
            let pointInCard = card.convert(point, from: self)
            if card.bounds.contains(pointInCard) {
                return card
            }
        }
        return super.hitTest(point)
    }

    private func cardView(for id: String) -> WorkspacePreviewCardView {
        if let card = cardViewsByID[id] {
            return card
        }

        let card = recycledCardViews.removeLast()
        cardViewsByID[id] = card
        addSubview(card)
        return card
    }

    private func recycleMissingCards(keeping ids: Set<String>) {
        for id in Array(cardViewsByID.keys) where !ids.contains(id) {
            guard let card = cardViewsByID.removeValue(forKey: id) else {
                continue
            }
            card.prepareForReuse()
            card.removeFromSuperview()
            recycledCardViews.append(card)
        }
    }
}

private struct WorkspaceCardConfiguration {
    let group: WorkspaceSwitcherGroup
    let isSelected: Bool
    let cardSize: NSSize
    let hoverGate: SwitcherHoverGate
    let onHover: (String) -> Void
    let onClick: (String) -> Void
}

private final class WorkspacePreviewCardView: NSView {
    private var workspaceID: String?
    private var hoverGate: SwitcherHoverGate?
    private var onHover: ((String) -> Void)?
    private var onClick: ((String) -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let previewSurface = NSView()
    private let previewImageView = NSImageView()
    private let fallbackLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        ))
    }

    override func mouseEntered(with _: NSEvent) {
        hover()
    }

    override func mouseMoved(with _: NSEvent) {
        hover()
    }

    override func mouseDown(with _: NSEvent) {
        commit()
    }

    override func rightMouseDown(with _: NSEvent) {
        commit()
    }

    override func otherMouseDown(with _: NSEvent) {
        commit()
    }

    func configure(_ configuration: WorkspaceCardConfiguration) {
        let group = configuration.group
        workspaceID = group.id
        hoverGate = configuration.hoverGate
        onHover = configuration.onHover
        onClick = configuration.onClick
        frame.size = configuration.cardSize
        titleLabel.stringValue = group.displayName
        layoutContent()
        update(group: group)
        updateSelection(configuration.isSelected)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        workspaceID = nil
        hoverGate = nil
        onHover = nil
        onClick = nil
        previewImageView.image = nil
    }

    func update(group: WorkspaceSwitcherGroup) {
        guard group.id == workspaceID else {
            return
        }

        subtitleLabel.stringValue = metadataText(for: group.windows)
        shortcutLabel.stringValue = group.shortcutKey?.uppercased() ?? ""
        shortcutLabel.isHidden = group.shortcutKey == nil
        previewImageView.image = group.preview
        previewImageView.isHidden = group.preview == nil
        fallbackLabel.stringValue = group.windows.isEmpty ? "No windows" : "Preview pending"
        fallbackLabel.isHidden = !group.windows.isEmpty && group.preview != nil
    }

    func updateSelection(_ isSelected: Bool) {
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
            : NSColor.black.withAlphaComponent(0.28).cgColor
        layer?.shadowOpacity = isSelected ? 0.36 : 0.22
        layer?.shadowRadius = isSelected ? 18 : 12
    }

    private func hover() {
        guard let workspaceID, hoverGate?.allowHoverIfPointerMoved() == true else {
            return
        }
        onHover?(workspaceID)
    }

    private func commit() {
        guard let workspaceID else {
            return
        }
        onClick?(workspaceID)
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -4)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail

        previewSurface.wantsLayer = true
        previewSurface.layer?.cornerRadius = 8
        previewSurface.layer?.masksToBounds = true
        previewSurface.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.36).cgColor
        previewSurface.layer?.borderWidth = 1
        previewSurface.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        previewImageView.imageScaling = .scaleAxesIndependently
        fallbackLabel.alignment = .center
        fallbackLabel.font = .systemFont(ofSize: 19.5, weight: .medium)
        fallbackLabel.textColor = .secondaryLabelColor
        shortcutLabel.alignment = .center
        shortcutLabel.textColor = NSColor.white.withAlphaComponent(0.5)
        shortcutLabel.maximumNumberOfLines = 1
        shortcutLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        previewSurface.addSubview(previewImageView)
        previewSurface.addSubview(fallbackLabel)
        previewSurface.addSubview(shortcutLabel)
        NSLayoutConstraint.activate([
            shortcutLabel.centerXAnchor.constraint(equalTo: previewSurface.centerXAnchor),
            shortcutLabel.centerYAnchor.constraint(equalTo: previewSurface.centerYAnchor),
            fallbackLabel.centerXAnchor.constraint(equalTo: previewSurface.centerXAnchor),
            fallbackLabel.topAnchor.constraint(equalTo: shortcutLabel.bottomAnchor, constant: 8)
        ])

        addSubview(previewSurface)
        addSubview(subtitleLabel)
        addSubview(titleLabel)
    }

    private func layoutContent() {
        let padding: CGFloat = 12
        let titleHeight: CGFloat = 22
        let subtitleHeight: CGFloat = 18
        titleLabel.frame = NSRect(
            x: padding,
            y: bounds.height - padding - titleHeight,
            width: bounds.width - padding * 2,
            height: titleHeight
        )
        subtitleLabel.frame = NSRect(
            x: padding,
            y: titleLabel.frame.minY - subtitleHeight,
            width: bounds.width - padding * 2,
            height: subtitleHeight
        )
        previewSurface.frame = NSRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: subtitleLabel.frame.minY - padding * 1.35
        )
        previewImageView.frame = previewSurface.bounds
        shortcutLabel.font = .systemFont(ofSize: previewSurface.bounds.height * 0.5, weight: .semibold)
    }

    private func metadataText(for windows: [WindowSwitcherItem]) -> String {
        guard !windows.isEmpty else {
            return ""
        }

        var appNames: [String] = []
        for window in windows where !appNames.contains(window.appName) {
            appNames.append(window.appName)
        }

        let visibleAppNames = appNames.prefix(2).joined(separator: ", ")
        let remainingAppCount = appNames.count - min(appNames.count, 2)
        let appText = remainingAppCount > 0
            ? "\(visibleAppNames) +\(remainingAppCount)"
            : visibleAppNames
        let windowText = windows.count == 1 ? "1 window" : "\(windows.count) windows"
        return "\(appText) - \(windowText)"
    }
}
