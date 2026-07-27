import AppKit
import CosmosCore

struct WindowTileMetrics {
    let width: CGFloat
    let height: CGFloat
    let previewHeight: CGFloat
    let columns: Int
    let spacing: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
}

private struct WindowTileConfiguration {
    let item: WindowSwitcherItem
    let isSelected: Bool
    let metrics: WindowTileMetrics
    let hoverGate: SwitcherHoverGate
    let onHover: ((WindowID) -> Void)?
    let onClick: ((WindowID) -> Void)?
}

final class WindowSwitcherListView: NSView {
    private var tileViewsByID: [WindowID: WindowSwitcherTileView] = [:]
    private var recycledTileViews: [WindowSwitcherTileView] = []
    private let hoverGate = SwitcherHoverGate()
    private let emptyLabel = NSTextField(labelWithString: "No windows")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        emptyLabel.font = .systemFont(ofSize: 15)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        addSubview(emptyLabel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
    }

    func ensureCapacity(_ count: Int) {
        let missingCount = max(0, count - tileViewsByID.count - recycledTileViews.count)
        for _ in 0 ..< missingCount {
            recycledTileViews.append(WindowSwitcherTileView(frame: .zero))
        }
    }

    func beginPresentation() {
        hoverGate.reset()
    }

    func configure(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        metrics: WindowTileMetrics,
        onHover: ((WindowID) -> Void)?,
        onClick: ((WindowID) -> Void)?
    ) {
        frame = NSRect(x: 0, y: 0, width: metrics.contentWidth, height: metrics.contentHeight)
        emptyLabel.frame = bounds
        emptyLabel.isHidden = !items.isEmpty
        recycleMissingTiles(keeping: Set(items.map(\.windowID)))
        ensureCapacity(items.count)

        for (index, item) in items.enumerated() {
            let tile = tileView(for: item.windowID)
            tile.configure(WindowTileConfiguration(
                item: item,
                isSelected: item.windowID == selectedID,
                metrics: metrics,
                hoverGate: hoverGate,
                onHover: onHover,
                onClick: onClick
            ))
            tile.frame.origin = tileOrigin(index: index, metrics: metrics)
        }
    }

    func updatePreviews(items: [WindowSwitcherItem]) {
        for item in items {
            tileViewsByID[item.windowID]?.updatePreview(item)
        }
    }

    func updateSelection(selectedID: WindowID) {
        for (id, tile) in tileViewsByID {
            tile.updateSelection(id == selectedID)
        }
    }

    private func tileView(for windowID: WindowID) -> WindowSwitcherTileView {
        if let tile = tileViewsByID[windowID] {
            return tile
        }

        let tile = recycledTileViews.removeLast()
        tileViewsByID[windowID] = tile
        addSubview(tile)
        return tile
    }

    private func recycleMissingTiles(keeping windowIDs: Set<WindowID>) {
        for windowID in Array(tileViewsByID.keys) where !windowIDs.contains(windowID) {
            guard let tile = tileViewsByID.removeValue(forKey: windowID) else {
                continue
            }
            tile.prepareForReuse()
            tile.removeFromSuperview()
            recycledTileViews.append(tile)
        }
    }

    private func tileOrigin(index: Int, metrics: WindowTileMetrics) -> NSPoint {
        let row = index / metrics.columns
        let column = index % metrics.columns
        return NSPoint(
            x: CGFloat(column) * (metrics.width + metrics.spacing),
            y: metrics.contentHeight
                - CGFloat(row + 1) * metrics.height
                - CGFloat(row) * metrics.spacing
        )
    }
}

final class WindowSwitcherTileView: NSView {
    private var windowID: WindowID?
    private var hoverGate: SwitcherHoverGate?
    private var onHover: ((WindowID) -> Void)?
    private var onClick: ((WindowID) -> Void)?
    private let appIconView = NSImageView()
    private let appLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let previewContainer = NSView()
    private let previewImageView = NSImageView()
    private let fallbackIconView = NSImageView()
    private let fallbackInitialLabel = NSTextField(labelWithString: "")

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
        guard let windowID else {
            return
        }
        onClick?(windowID)
    }

    fileprivate func configure(_ configuration: WindowTileConfiguration) {
        let item = configuration.item
        let metrics = configuration.metrics
        windowID = item.windowID
        hoverGate = configuration.hoverGate
        onHover = configuration.onHover
        onClick = configuration.onClick
        frame.size = NSSize(width: metrics.width, height: metrics.height)

        let padding: CGFloat = 8
        let isNarrow = metrics.width < 120
        let iconSize: CGFloat = isNarrow ? 14 : 18
        let titleHeight: CGFloat = isNarrow ? 14 : 16
        let appLabelHeight: CGFloat = isNarrow ? 14 : 16
        previewContainer.frame = NSRect(
            x: padding,
            y: padding,
            width: metrics.width - padding * 2,
            height: metrics.previewHeight
        )
        titleLabel.frame = NSRect(
            x: padding,
            y: previewContainer.frame.maxY + 3,
            width: metrics.width - padding * 2,
            height: titleHeight
        )
        let appRowY = titleLabel.frame.maxY + (isNarrow ? 3 : 4)
        appIconView.frame = NSRect(x: padding, y: appRowY, width: iconSize, height: iconSize)
        appLabel.frame = NSRect(
            x: appIconView.frame.maxX + 6,
            y: appRowY + floor((iconSize - appLabelHeight) / 2),
            width: metrics.width - padding * 2 - iconSize - 6,
            height: appLabelHeight
        )

        appLabel.stringValue = item.appName
        appLabel.font = .systemFont(ofSize: isNarrow ? 11 : 12, weight: .semibold)
        titleLabel.stringValue = item.displayTitle
        titleLabel.font = .systemFont(ofSize: isNarrow ? 10 : 11)
        layoutPreviewContent()
        updatePreview(item)
        updateSelection(configuration.isSelected)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        windowID = nil
        hoverGate = nil
        onHover = nil
        onClick = nil
        appIconView.image = nil
        previewImageView.image = nil
        fallbackIconView.image = nil
    }

    func updatePreview(_ item: WindowSwitcherItem) {
        guard item.windowID == windowID else {
            return
        }

        appIconView.image = item.icon
        previewImageView.image = item.preview
        previewImageView.isHidden = item.preview == nil
        fallbackIconView.image = item.icon
        fallbackIconView.isHidden = item.preview != nil || item.icon == nil
        fallbackInitialLabel.stringValue = item.appName.first.map(String.init) ?? "?"
        fallbackInitialLabel.isHidden = item.preview != nil || item.icon != nil
    }

    func updateSelection(_ isSelected: Bool) {
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            : NSColor.black.withAlphaComponent(0.22).cgColor
    }

    private func hover() {
        guard let windowID, hoverGate?.allowHoverIfPointerMoved() == true else {
            return
        }
        onHover?(windowID)
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 8
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        appLabel.textColor = .white
        appLabel.maximumNumberOfLines = 1
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        previewContainer.wantsLayer = true
        previewContainer.layer?.cornerRadius = 6
        previewContainer.layer?.masksToBounds = true
        previewContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackIconView.imageScaling = .scaleProportionallyUpOrDown
        fallbackInitialLabel.alignment = .center
        fallbackInitialLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        fallbackInitialLabel.textColor = .white
        previewContainer.addSubview(previewImageView)
        previewContainer.addSubview(fallbackIconView)
        previewContainer.addSubview(fallbackInitialLabel)

        addSubview(appIconView)
        addSubview(appLabel)
        addSubview(titleLabel)
        addSubview(previewContainer)
    }

    private func layoutPreviewContent() {
        previewImageView.frame = previewContainer.bounds
        fallbackIconView.frame = previewContainer.bounds.insetBy(
            dx: previewContainer.bounds.width * 0.17,
            dy: previewContainer.bounds.height * 0.17
        )
        fallbackInitialLabel.frame = previewContainer.bounds
    }
}
