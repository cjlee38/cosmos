import AppKit
import CosmosCore

enum SpaceDragPayload {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.cosmos.space-id")

    static func pasteboardItem(for spaceID: SpaceID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(spaceID.rawValue, forType: pasteboardType)
        return item
    }

    static func spaceID(from pasteboard: NSPasteboard) -> SpaceID? {
        pasteboard.string(forType: pasteboardType).flatMap(SpaceID.init(rawValue:))
    }
}

final class SpaceDisplayArrangementView: NSView {
    var onDisplaySelected: ((DisplayID) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onSpaceSelected: ((SpaceID) -> Void)?
    var onSpaceMoved: ((SpaceID, DisplayID) -> Void)?

    private let scrollView = SpaceDisplayScrollView()
    private let canvasView = SpaceDisplayCanvasView()
    private var contentHeight: CGFloat = 210

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = canvasView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        canvasView.onDisplaySelected = { [weak self] in self?.onDisplaySelected?($0) }
        canvasView.onSelectionCleared = { [weak self] in self?.onSelectionCleared?() }
        canvasView.onSpaceSelected = { [weak self] in self?.onSpaceSelected?($0) }
        canvasView.onSpaceMoved = { [weak self] in self?.onSpaceMoved?($0, $1) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
    }

    override func layout() {
        super.layout()
        let canvasSize = canvasView.layoutContent(fittingWidth: max(bounds.width, 1))
        canvasView.frame = NSRect(origin: .zero, size: canvasSize)
        if abs(contentHeight - canvasSize.height) > 0.5 {
            contentHeight = canvasSize.height
            invalidateIntrinsicContentSize()
        }
    }

    func apply(
        _ displays: [SpaceSettingsDisplay],
        selectedDisplayID: DisplayID?,
        selectedSpaceID: SpaceID?,
        isEditable: Bool
    ) {
        canvasView.apply(
            displays,
            selectedDisplayID: selectedDisplayID,
            selectedSpaceID: selectedSpaceID,
            isEditable: isEditable
        )
        needsLayout = true
    }
}

private final class SpaceDisplayScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX),
              let parentScrollView
        else {
            super.scrollWheel(with: event)
            return
        }
        parentScrollView.scrollWheel(with: event)
    }

    private var parentScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            ancestor = view.superview
        }
        return nil
    }
}

private final class SpaceDisplayCanvasView: NSView {
    var onDisplaySelected: ((DisplayID) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onSpaceSelected: ((SpaceID) -> Void)?
    var onSpaceMoved: ((SpaceID, DisplayID) -> Void)?

    private static let minimumCardSize = NSSize(width: 210, height: 130)
    private static let preferredCardSize = NSSize(width: 320, height: 200)
    private static let minimumCanvasHeight: CGFloat = 210
    private static let padding: CGFloat = 14

    private var displayCards: [(item: SpaceSettingsDisplay, view: SpaceDisplayCardView)] = []
    private let emptyLabel = NSTextField(labelWithString: "No displays detected")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
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

    override func mouseDown(with _: NSEvent) {
        onSelectionCleared?()
    }

    func apply(
        _ displays: [SpaceSettingsDisplay],
        selectedDisplayID: DisplayID?,
        selectedSpaceID: SpaceID?,
        isEditable: Bool
    ) {
        displayCards.forEach { $0.view.removeFromSuperview() }
        displayCards = displays.map { item in
            let card = SpaceDisplayCardView(
                item: item,
                isSelected: item.id == selectedDisplayID,
                selectedSpaceID: selectedSpaceID,
                isEditable: isEditable
            )
            card.onSelect = { [weak self] in self?.onDisplaySelected?(item.id) }
            card.onSpaceSelected = { [weak self] in self?.onSpaceSelected?($0) }
            card.onSpaceMoved = { [weak self] in self?.onSpaceMoved?($0, item.id) }
            addSubview(card)
            return (item, card)
        }
        emptyLabel.isHidden = !displayCards.isEmpty
    }

    func layoutContent(fittingWidth viewportWidth: CGFloat) -> NSSize {
        guard let firstCard = displayCards.first else {
            emptyLabel.frame = NSRect(x: 0, y: 0, width: viewportWidth, height: Self.minimumCanvasHeight)
            return NSSize(width: viewportWidth, height: Self.minimumCanvasHeight)
        }

        let desktopBounds = displayCards.dropFirst().reduce(firstCard.item.frame) {
            $0.union($1.item.frame)
        }
        guard desktopBounds.width > 0, desktopBounds.height > 0 else {
            return NSSize(width: viewportWidth, height: Self.minimumCanvasHeight)
        }

        let fitScale = max(viewportWidth - Self.padding * 2, 1) / desktopBounds.width
        let minimumScale = displayCards.map { card in
            max(
                Self.minimumCardSize.width / card.item.frame.width,
                Self.minimumCardSize.height / card.item.frame.height
            )
        }.max() ?? fitScale
        let preferredScale = displayCards.map { card in
            min(
                Self.preferredCardSize.width / card.item.frame.width,
                Self.preferredCardSize.height / card.item.frame.height
            )
        }.min() ?? fitScale
        let scale = max(min(fitScale, preferredScale), minimumScale)
        let renderedSize = NSSize(
            width: desktopBounds.width * scale,
            height: desktopBounds.height * scale
        )
        let canvasSize = NSSize(
            width: max(viewportWidth, renderedSize.width + Self.padding * 2),
            height: max(Self.minimumCanvasHeight, renderedSize.height + Self.padding * 2)
        )
        let renderedOrigin = NSPoint(
            x: (canvasSize.width - renderedSize.width) / 2,
            y: (canvasSize.height - renderedSize.height) / 2
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
        return canvasSize
    }
}
