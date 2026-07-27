import AppKit
import CosmosCore

struct SpaceSwitcherInteractions {
    let onHover: (String) -> Void
    let onClick: (String) -> Void
}

final class SpaceSwitcherListView: NSView {
    private var cardViewsByID: [String: SpacePreviewCardView] = [:]
    private var recycledCardViews: [SpacePreviewCardView] = []
    private let hoverGate = SwitcherHoverGate()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
    }

    func ensureCapacity(_ count: Int) {
        let missingCount = max(0, count - cardViewsByID.count - recycledCardViews.count)
        for _ in 0 ..< missingCount {
            recycledCardViews.append(SpacePreviewCardView(frame: .zero))
        }
    }

    func beginPresentation() {
        hoverGate.reset()
    }

    func configure(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        availableFrame: NSRect,
        size: CGFloat,
        interactions: SpaceSwitcherInteractions
    ) {
        let layout = SpaceOverviewLayout(
            groupCount: groups.count,
            availableFrame: availableFrame,
            size: size
        )
        frame = NSRect(origin: .zero, size: layout.contentSize)
        recycleMissingCards(keeping: Set(groups.map(\.id)))
        ensureCapacity(groups.count)

        for (index, group) in groups.enumerated() {
            let row = index / layout.columns
            let column = index % layout.columns
            let cell = layout.cellFrame(row: row, column: column)
            let card = cardView(for: group.id)
            card.configure(SpaceCardConfiguration(
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

    func updatePreviews(groups: [SpaceSwitcherGroup]) {
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

    private func cardView(for id: String) -> SpacePreviewCardView {
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

private struct SpaceCardConfiguration {
    let group: SpaceSwitcherGroup
    let isSelected: Bool
    let cardSize: NSSize
    let hoverGate: SwitcherHoverGate
    let onHover: (String) -> Void
    let onClick: (String) -> Void
}

private final class SpacePreviewCardView: NSView {
    private var spaceID: String?
    private var hoverGate: SwitcherHoverGate?
    private var onHover: ((String) -> Void)?
    private var onClick: ((String) -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let previewSurface = NSView()
    private let previewImageView = NSImageView()
    private let applicationIconStrip = SpaceApplicationIconStripView()
    private let fallbackLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
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

    func configure(_ configuration: SpaceCardConfiguration) {
        let group = configuration.group
        spaceID = group.id
        hoverGate = configuration.hoverGate
        onHover = configuration.onHover
        onClick = configuration.onClick
        frame.size = configuration.cardSize
        titleLabel.stringValue = group.id
        update(group: group)
        layoutContent()
        updateSelection(configuration.isSelected)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        spaceID = nil
        hoverGate = nil
        onHover = nil
        onClick = nil
        previewImageView.image = nil
        applicationIconStrip.update(windows: [], isVisible: false)
    }

    func update(group: SpaceSwitcherGroup) {
        guard group.id == spaceID else {
            return
        }

        subtitleLabel.stringValue = metadataText(for: group.windows)
        shortcutLabel.stringValue = group.shortcutKey?.uppercased() ?? ""
        shortcutLabel.isHidden = group.shortcutKey == nil
        previewImageView.image = group.preview
        previewImageView.isHidden = group.previewStyle != .spatial || group.preview == nil
        applicationIconStrip.update(
            windows: group.windows,
            isVisible: group.previewStyle == .applicationIcons
        )
        fallbackLabel.stringValue = group.windows.isEmpty ? "No windows" : "Preview pending"
        fallbackLabel.isHidden = group.windows.isEmpty
            ? false
            : (group.previewStyle == .applicationIcons && applicationIconStrip.hasVisibleIcon)
            || (group.previewStyle == .spatial && group.preview != nil)
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
        guard let spaceID, hoverGate?.allowHoverIfPointerMoved() == true else {
            return
        }
        onHover?(spaceID)
    }

    private func commit() {
        guard let spaceID else {
            return
        }
        onClick?(spaceID)
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
        previewSurface.addSubview(previewImageView)
        previewSurface.addSubview(applicationIconStrip)
        previewSurface.addSubview(fallbackLabel)
        previewSurface.addSubview(shortcutLabel)

        addSubview(previewSurface)
        addSubview(subtitleLabel)
        addSubview(titleLabel)
    }

    private func layoutContent() {
        let scale = min(1, max(0.45, bounds.height / 180))
        let padding = max(4, floor(12 * scale))
        let titleHeight = max(10, floor(22 * scale))
        let subtitleHeight = max(8, floor(18 * scale))
        titleLabel.font = .systemFont(ofSize: max(9, floor(15 * scale)), weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: max(7, floor(12 * scale)))
        subtitleLabel.isHidden = bounds.height < 80
        titleLabel.frame = NSRect(
            x: padding,
            y: bounds.height - padding - titleHeight,
            width: bounds.width - padding * 2,
            height: titleHeight
        )
        let subtitleBottom = subtitleLabel.isHidden
            ? titleLabel.frame.minY
            : titleLabel.frame.minY - subtitleHeight
        subtitleLabel.frame = NSRect(
            x: padding,
            y: subtitleBottom,
            width: max(1, bounds.width - padding * 2),
            height: subtitleLabel.isHidden ? 0 : subtitleHeight
        )
        previewSurface.frame = NSRect(
            x: padding,
            y: padding,
            width: max(1, bounds.width - padding * 2),
            height: max(1, subtitleBottom - padding * 1.35)
        )
        previewImageView.frame = previewSurface.bounds
        applicationIconStrip.frame = previewSurface.bounds
        shortcutLabel.font = .systemFont(ofSize: previewSurface.bounds.height * 0.5, weight: .semibold)
        shortcutLabel.sizeToFit()
        shortcutLabel.frame = NSRect(
            x: 0,
            y: floor(previewSurface.bounds.midY - shortcutLabel.frame.height / 2),
            width: previewSurface.bounds.width,
            height: shortcutLabel.frame.height
        )
        fallbackLabel.font = .systemFont(ofSize: max(8, floor(19.5 * scale)), weight: .medium)
        fallbackLabel.sizeToFit()
        let fallbackY = shortcutLabel.isHidden
            ? previewSurface.bounds.midY - fallbackLabel.frame.height / 2
            : previewSurface.bounds.midY - shortcutLabel.intrinsicContentSize.height / 2
            - 8 - fallbackLabel.frame.height
        fallbackLabel.frame.origin = NSPoint(
            x: previewSurface.bounds.midX - fallbackLabel.frame.width / 2,
            y: max(0, fallbackY)
        )
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
