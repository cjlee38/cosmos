import AppKit

final class WorkspaceSwitcherListView: NSView {
    private var cardViewsByName: [String: WorkspacePreviewCardView] = [:]

    init(
        groups: [WorkspaceSwitcherGroup],
        selectedIndex: Int,
        availableFrame: NSRect,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) {
        let layout = WorkspaceOverviewLayout(groupCount: groups.count, availableFrame: availableFrame)
        super.init(frame: NSRect(origin: .zero, size: layout.contentSize))
        setup(
            groups: groups,
            selectedIndex: selectedIndex,
            layout: layout,
            onHover: onHover,
            onClick: onClick
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreviews(groups: [WorkspaceSwitcherGroup]) {
        for group in groups {
            cardViewsByName[group.name]?.update(group: group)
        }
    }

    func updateSelection(selectedName: String) {
        for (name, card) in cardViewsByName {
            card.updateSelection(name == selectedName)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for card in cardViewsByName.values.reversed() {
            let pointInCard = card.convert(point, from: self)
            if card.bounds.contains(pointInCard) {
                return card
            }
        }

        return super.hitTest(point)
    }

    private func setup(
        groups: [WorkspaceSwitcherGroup],
        selectedIndex: Int,
        layout: WorkspaceOverviewLayout,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) {
        let hoverGate = SwitcherHoverGate()
        for (index, group) in groups.enumerated() {
            let row = index / layout.columns
            let column = index % layout.columns
            let cell = layout.cellFrame(row: row, column: column)
            let card = WorkspacePreviewCardView(
                group: group,
                isSelected: index == selectedIndex,
                cardSize: layout.cardSize,
                hoverGate: hoverGate,
                onHover: onHover,
                onClick: onClick
            )
            card.frame.origin = NSPoint(
                x: cell.midX - layout.cardSize.width / 2,
                y: cell.midY - layout.cardSize.height / 2
            )
            addSubview(card)
            cardViewsByName[group.name] = card
        }
    }
}

private struct WorkspaceOverviewLayout {
    let contentSize: NSSize
    let cardSize: NSSize
    let columns: Int
    private let rows: Int
    private let spacing: CGFloat

    init(groupCount: Int, availableFrame: NSRect) {
        let count = max(groupCount, 1)
        let spacing: CGFloat = 24
        let columns = Self.columnCount(groupCount: count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let contentSize = NSSize(
            width: floor(availableFrame.width * 0.90),
            height: floor(availableFrame.height * 0.82)
        )
        let cellWidth = (contentSize.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let cellHeight = (contentSize.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        let screenAspect = min(max(availableFrame.width / max(availableFrame.height, 1), 1.35), 1.9)
        let chromeHeight: CGFloat = 82
        let horizontalChrome: CGFloat = 24
        let maxCanvasWidth = max(160, cellWidth - horizontalChrome)
        let maxCanvasHeight = max(100, cellHeight - chromeHeight)
        let canvasWidth = min(maxCanvasWidth, maxCanvasHeight * screenAspect)
        let canvasHeight = canvasWidth / screenAspect

        self.contentSize = contentSize
        cardSize = NSSize(width: canvasWidth + horizontalChrome, height: canvasHeight + chromeHeight)
        self.columns = columns
        self.rows = rows
        self.spacing = spacing
    }

    func cellFrame(row: Int, column: Int) -> NSRect {
        let cellWidth = (contentSize.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let cellHeight = (contentSize.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        return NSRect(
            x: CGFloat(column) * (cellWidth + spacing),
            y: contentSize.height - CGFloat(row + 1) * cellHeight - CGFloat(row) * spacing,
            width: cellWidth,
            height: cellHeight
        )
    }

    private static func columnCount(groupCount: Int) -> Int {
        switch groupCount {
        case ...1:
            1
        case 2 ... 3:
            groupCount
        case 4:
            2
        case 5 ... 6:
            3
        default:
            Int(ceil(sqrt(Double(groupCount))))
        }
    }
}

private final class WorkspacePreviewCardView: NSView {
    private let name: String
    private let hoverGate: SwitcherHoverGate
    private let onHover: (String) -> Void
    private let onClick: (String) -> Void
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let previewImageView = NSImageView()
    private let fallbackLabel = NSTextField(labelWithString: "")

    init(
        group: WorkspaceSwitcherGroup,
        isSelected: Bool,
        cardSize: NSSize,
        hoverGate: SwitcherHoverGate,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) {
        name = group.name
        self.hoverGate = hoverGate
        self.onHover = onHover
        self.onClick = onClick
        super.init(frame: NSRect(origin: .zero, size: cardSize))
        setupChrome()
        setupContent(group: group)
        updateSelection(isSelected)
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
        onClick(name)
    }

    override func rightMouseDown(with _: NSEvent) {
        onClick(name)
    }

    override func otherMouseDown(with _: NSEvent) {
        onClick(name)
    }

    private func hover() {
        guard hoverGate.allowHoverIfPointerMoved() else {
            return
        }

        onHover(name)
    }

    func update(group: WorkspaceSwitcherGroup) {
        subtitleLabel.stringValue = metadataText(for: group.windows)
        previewImageView.image = group.preview
        previewImageView.isHidden = group.preview == nil
        fallbackLabel.stringValue = group.windows.isEmpty ? "No windows" : "Preview pending"
        fallbackLabel.isHidden = group.preview != nil
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

    private func setupChrome() {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOffset = NSSize(width: 0, height: -4)
    }

    private func setupContent(group: WorkspaceSwitcherGroup) {
        let padding: CGFloat = 12
        let titleHeight: CGFloat = 22
        let subtitleHeight: CGFloat = 18
        let title = label(
            "Workspace \(group.name)",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .white
        )
        title.frame = NSRect(
            x: padding,
            y: bounds.height - padding - titleHeight,
            width: bounds.width - padding * 2,
            height: titleHeight
        )

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(
            x: padding,
            y: title.frame.minY - subtitleHeight,
            width: bounds.width - padding * 2,
            height: subtitleHeight
        )

        let previewFrame = NSRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: subtitleLabel.frame.minY - padding * 1.35
        )
        let previewSurface = makePreviewSurface(frame: previewFrame)
        previewSurface.addSubview(previewImageView)
        previewSurface.addSubview(fallbackLabel)

        addSubview(previewSurface)
        addSubview(subtitleLabel)
        addSubview(title)
        update(group: group)
    }

    private func makePreviewSurface(frame: NSRect) -> NSView {
        let surface = NSView(frame: frame)
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 8
        surface.layer?.masksToBounds = true
        surface.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.36).cgColor
        surface.layer?.borderWidth = 1
        surface.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        previewImageView.frame = surface.bounds
        previewImageView.autoresizingMask = [.width, .height]
        previewImageView.imageScaling = .scaleAxesIndependently

        fallbackLabel.frame = surface.bounds
        fallbackLabel.autoresizingMask = [.width, .height]
        fallbackLabel.alignment = .center
        fallbackLabel.font = .systemFont(ofSize: 13, weight: .medium)
        fallbackLabel.textColor = .secondaryLabelColor

        return surface
    }

    private func metadataText(for windows: [WindowSwitcherItem]) -> String {
        guard !windows.isEmpty else {
            return "No windows"
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

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        return field
    }
}
