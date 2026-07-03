import AppKit
import KkaciCore

final class SwitcherOverlayViewFactory {
    func makeRootContent(title: String?, content: NSView) -> NSView {
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 18
        let titleSpacing: CGFloat = title == nil ? 0 : 12
        let titleHeight: CGFloat = title == nil ? 0 : 22
        let rootSize = NSSize(
            width: content.frame.width + horizontalPadding * 2,
            height: content.frame.height + verticalPadding * 2 + titleSpacing + titleHeight
        )

        let root = NSView(frame: NSRect(origin: .zero, size: rootSize))
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true

        let background = NSVisualEffectView(frame: root.bounds)
        background.autoresizingMask = [.width, .height]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.alphaValue = 0.89
        background.wantsLayer = true
        background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        root.addSubview(background)

        content.frame.origin = NSPoint(x: horizontalPadding, y: verticalPadding)
        root.addSubview(content)

        if let title {
            let titleLabel = label(title, font: .systemFont(ofSize: 16, weight: .semibold), color: .white)
            titleLabel.frame = NSRect(
                x: horizontalPadding,
                y: verticalPadding + content.frame.height + titleSpacing,
                width: content.frame.width,
                height: titleHeight
            )
            root.addSubview(titleLabel)
        }

        return root
    }

    func makeWindowList(
        items: [WindowSwitcherItem],
        selectedIndex: Int,
        availableFrame: NSRect,
        onHover: ((WindowID) -> Void)? = nil,
        onClick: ((WindowID) -> Void)? = nil
    ) -> WindowSwitcherListView {
        let metrics = tileMetrics(count: items.count, availableFrame: availableFrame)
        let frame = NSRect(x: 0, y: 0, width: metrics.contentWidth, height: metrics.contentHeight)
        let listView = WindowSwitcherListView(frame: frame)

        if items.isEmpty {
            let empty = label("No windows", font: .systemFont(ofSize: 15), color: .secondaryLabelColor)
            empty.alignment = .center
            empty.frame = frame
            listView.addSubview(empty)
            return listView
        }

        for (index, item) in items.enumerated() {
            let tile = WindowSwitcherTileView(
                item: item,
                isSelected: index == selectedIndex,
                metrics: metrics,
                onHover: onHover,
                onClick: onClick
            )
            tile.frame.origin = tileOrigin(index: index, metrics: metrics)
            listView.addTile(tile, id: item.id)
        }

        return listView
    }

    func makeWorkspaceList(
        groups: [WorkspaceSwitcherGroup],
        selectedIndex: Int,
        availableFrame: NSRect
    ) -> WorkspaceSwitcherListView {
        WorkspaceSwitcherListView(
            groups: groups,
            selectedIndex: selectedIndex,
            availableFrame: availableFrame
        )
    }

    private func tileMetrics(count: Int, availableFrame: NSRect) -> WindowTileMetrics {
        let spacing: CGFloat = 10
        let targetWidth = targetTileWidth(count: count)
        let minWidth: CGFloat = 104
        let maxContentWidth = max(minWidth, availableFrame.width * 0.86)
        let itemCount = max(count, 1)
        let maxColumns = max(1, Int((maxContentWidth + spacing) / (minWidth + spacing)))
        let columns = max(1, min(itemCount, maxColumns))
        let widthThatFits = (maxContentWidth - CGFloat(max(columns - 1, 0)) * spacing) / CGFloat(columns)
        let tileWidth = min(targetWidth, max(minWidth, floor(widthThatFits)))
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let previewHeight = max(68, min(174, floor(tileWidth * 0.62)))
        let tileHeight = previewHeight + (tileWidth < 120 ? 50 : 57)
        let contentWidth = CGFloat(columns) * tileWidth + CGFloat(max(columns - 1, 0)) * spacing
        let contentHeight = CGFloat(rows) * tileHeight + CGFloat(max(rows - 1, 0)) * spacing

        return WindowTileMetrics(
            width: tileWidth,
            height: tileHeight,
            previewHeight: previewHeight,
            columns: columns,
            spacing: spacing,
            contentWidth: contentWidth,
            contentHeight: contentHeight
        )
    }

    private func targetTileWidth(count: Int) -> CGFloat {
        switch count {
        case ...1:
            return 280
        case 2:
            return 240
        case 3:
            return 210
        case 4:
            return 185
        default:
            return 168
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

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        return field
    }
}

private struct WindowTileMetrics {
    let width: CGFloat
    let height: CGFloat
    let previewHeight: CGFloat
    let columns: Int
    let spacing: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
}

final class WindowSwitcherListView: NSView {
    private(set) var tileViewsByID: [WindowID: [WindowSwitcherTileView]] = [:]

    func addTile(_ tile: WindowSwitcherTileView, id: WindowID) {
        tileViewsByID[id, default: []].append(tile)
        addSubview(tile)
    }

    func updatePreviews(items: [WindowSwitcherItem]) {
        for item in items {
            tileViewsByID[item.id]?.forEach { $0.updatePreview(item) }
        }
    }

    func updateSelection(selectedID: WindowID) {
        for (id, tiles) in tileViewsByID {
            tiles.forEach { $0.updateSelection(id == selectedID) }
        }
    }
}

final class WindowSwitcherTileView: NSView {
    private let id: WindowID
    private let onHover: ((WindowID) -> Void)?
    private let onClick: ((WindowID) -> Void)?
    private let appIconView = NSImageView()
    private let previewImageView = NSImageView()
    private let fallbackIconView = NSImageView()
    private let fallbackInitialLabel = NSTextField(labelWithString: "")

    fileprivate init(
        item: WindowSwitcherItem,
        isSelected: Bool,
        metrics: WindowTileMetrics,
        onHover: ((WindowID) -> Void)?,
        onClick: ((WindowID) -> Void)?
    ) {
        self.id = item.id
        self.onHover = onHover
        self.onClick = onClick
        super.init(frame: NSRect(x: 0, y: 0, width: metrics.width, height: metrics.height))
        setup(item: item, metrics: metrics)
        updateSelection(isSelected)
        updatePreview(item)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(id)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(id)
    }

    func updatePreview(_ item: WindowSwitcherItem) {
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

    private func setup(item: WindowSwitcherItem, metrics: WindowTileMetrics) {
        wantsLayer = true
        layer?.cornerRadius = 8

        let padding: CGFloat = 8
        let isNarrow = metrics.width < 120
        let iconSize: CGFloat = isNarrow ? 14 : 18
        let titleHeight: CGFloat = isNarrow ? 14 : 16
        let appLabelHeight: CGFloat = isNarrow ? 14 : 16
        let preview = makePreviewContainer()
        appIconView.image = item.icon
        appIconView.imageScaling = .scaleProportionallyUpOrDown
        let appLabel = label(
            item.appName,
            font: .systemFont(ofSize: isNarrow ? 11 : 12, weight: .semibold),
            color: .white
        )
        let titleLabel = label(
            item.displayTitle,
            font: .systemFont(ofSize: isNarrow ? 10 : 11),
            color: .secondaryLabelColor
        )
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.lineBreakMode = .byTruncatingTail

        preview.frame = NSRect(
            x: padding,
            y: padding,
            width: metrics.width - padding * 2,
            height: metrics.previewHeight
        )
        titleLabel.frame = NSRect(
            x: padding,
            y: preview.frame.maxY + 3,
            width: metrics.width - padding * 2,
            height: titleHeight
        )
        let appRowY = titleLabel.frame.maxY + (isNarrow ? 3 : 4)
        appIconView.frame = NSRect(
            x: padding,
            y: appRowY,
            width: iconSize,
            height: iconSize
        )
        appLabel.frame = NSRect(
            x: appIconView.frame.maxX + 6,
            y: appRowY + floor((iconSize - appLabelHeight) / 2),
            width: metrics.width - padding * 2 - iconSize - 6,
            height: appLabelHeight
        )

        addSubview(appIconView)
        addSubview(appLabel)
        addSubview(titleLabel)
        addSubview(preview)
    }

    private func makePreviewContainer() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackIconView.imageScaling = .scaleProportionallyUpOrDown
        fallbackInitialLabel.alignment = .center
        fallbackInitialLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        fallbackInitialLabel.textColor = .white

        container.addSubview(previewImageView)
        container.addSubview(fallbackIconView)
        container.addSubview(fallbackInitialLabel)
        return container
    }

    override func layout() {
        super.layout()
        guard let previewContainer = previewImageView.superview else {
            return
        }
        previewImageView.frame = previewContainer.bounds
        fallbackIconView.frame = previewContainer.bounds.insetBy(dx: previewContainer.bounds.width * 0.28, dy: previewContainer.bounds.height * 0.28)
        fallbackInitialLabel.frame = previewContainer.bounds
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        return field
    }
}
