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

private final class SpaceDisplayCardView: NSView {
    private static let parkingGuideURL = "<TODO>"

    var onSelect: (() -> Void)?
    var onSpaceSelected: ((SpaceID) -> Void)?
    var onSpaceMoved: ((SpaceID) -> Void)?

    private let isSelected: Bool
    private let isEditable: Bool
    private let isParkingObstructed: Bool
    private var isDropTarget = false
    private let spaceFlow: SpacePillFlowView
    private var overflowPopover: NSPopover?
    private var parkingWarningPopover: NSPopover?
    private let parkingWarning = NSButton()

    init(
        item: SpaceSettingsDisplay,
        isSelected: Bool,
        selectedSpaceID: SpaceID?,
        isEditable: Bool
    ) {
        self.isSelected = isSelected
        self.isEditable = isEditable
        isParkingObstructed = !item.hasUnobstructedParkingCorner
        spaceFlow = SpacePillFlowView(
            spaceIDs: item.spaceIDs,
            selectedSpaceID: selectedSpaceID
        )
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityIdentifier("cosmos.settings.display.\(item.monitorSlot)")
        registerForDraggedTypes([SpaceDragPayload.pasteboardType])

        let parkingMessage = "No unobstructed parking corner is available. "
            + "Hidden windows may remain visible and clickable on another display. "
            + "Rearrange the displays in System Settings."
        toolTip = isParkingObstructed ? parkingMessage : nil

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

        parkingWarning.image = NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: "Unsafe display arrangement"
        )
        parkingWarning.isBordered = false
        parkingWarning.contentTintColor = .systemRed
        parkingWarning.toolTip = isParkingObstructed ? parkingMessage : nil
        parkingWarning.isHidden = !isParkingObstructed
        parkingWarning.target = self
        parkingWarning.action = #selector(showParkingWarning)
        parkingWarning.translatesAutoresizingMaskIntoConstraints = false
        parkingWarning.setAccessibilityIdentifier(
            "cosmos.settings.display-parking-warning.\(item.monitorSlot)"
        )

        spaceFlow.translatesAutoresizingMaskIntoConstraints = false
        spaceFlow.onSpaceSelected = { [weak self] spaceID in
            self?.onSpaceSelected?(spaceID)
        }
        spaceFlow.onOverflowSelected = { [weak self] spaceIDs, sourceView in
            self?.showOverflow(spaceIDs, relativeTo: sourceView)
        }

        addSubview(heading)
        addSubview(parkingWarning)
        addSubview(spaceFlow)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: parkingWarning.leadingAnchor, constant: -7),
            parkingWarning.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            parkingWarning.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            parkingWarning.widthAnchor.constraint(equalToConstant: 17),
            parkingWarning.heightAnchor.constraint(equalToConstant: 17),
            spaceFlow.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 8),
            spaceFlow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            spaceFlow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            spaceFlow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9)
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
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = isParkingObstructed || isDropTarget ? 2 : 1
        layer?.cornerRadius = 7
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else {
            return nil
        }
        if hitView is NSButton || hitView is SpacePillView {
            return hitView
        }
        return self
    }

    override func mouseDown(with _: NSEvent) {
        onSelect?()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable,
              SpaceDragPayload.spaceID(from: sender.draggingPasteboard) != nil
        else {
            return []
        }
        isDropTarget = true
        needsDisplay = true
        return .move
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        isDropTarget = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer {
            isDropTarget = false
            needsDisplay = true
        }
        guard isEditable,
              let spaceID = SpaceDragPayload.spaceID(from: sender.draggingPasteboard)
        else {
            return false
        }
        onSpaceMoved?(spaceID)
        return true
    }

    private var borderColor: NSColor {
        if isParkingObstructed {
            return .systemRed
        }
        return isDropTarget ? .controlAccentColor : .separatorColor
    }

    private func showOverflow(_ spaceIDs: [SpaceID], relativeTo sourceView: NSView) {
        guard !spaceIDs.isEmpty else {
            return
        }
        overflowPopover?.close()

        let content = SpaceOverflowViewController(
            spaceIDs: spaceIDs,
            onSpaceSelected: { [weak self] spaceID in
                self?.overflowPopover?.close()
                self?.onSpaceSelected?(spaceID)
            }
        )
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = content
        popover.contentSize = content.popoverContentSize
        overflowPopover = popover
        popover.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    @objc private func showParkingWarning() {
        parkingWarningPopover?.close()
        let content = ParkingWarningViewController(
            message: parkingWarning.toolTip ?? "",
            detailsURL: Self.parkingGuideURL
        )
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentViewController = content
        popover.contentSize = content.popoverContentSize
        parkingWarningPopover = popover
        popover.show(relativeTo: parkingWarning.bounds, of: parkingWarning, preferredEdge: .maxY)
    }
}

private final class SpacePillFlowView: NSView {
    var onSpaceSelected: ((SpaceID) -> Void)?
    var onOverflowSelected: (([SpaceID], NSView) -> Void)?

    private let spaceIDs: [SpaceID]
    private var pills: [SpacePillView] = []
    private let overflowPill = SpaceOverflowPillView()
    private let emptyLabel = NSTextField(labelWithString: "No spaces")

    init(spaceIDs: [SpaceID], selectedSpaceID: SpaceID?) {
        self.spaceIDs = spaceIDs
        super.init(frame: .zero)
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor
        addSubview(emptyLabel)
        addSubview(overflowPill)
        overflowPill.onSelect = { [weak self] sourceView in
            guard let self else {
                return
            }
            onOverflowSelected?(hiddenSpaceIDs, sourceView)
        }

        pills = spaceIDs.map { spaceID in
            let pill = SpacePillView(
                spaceID: spaceID,
                isSelected: spaceID == selectedSpaceID
            )
            pill.onSelect = { [weak self] id in self?.onSpaceSelected?(id) }
            addSubview(pill)
            return pill
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override func layout() {
        super.layout()
        emptyLabel.frame = bounds
        emptyLabel.isHidden = !pills.isEmpty
        overflowPill.isHidden = true
        guard !pills.isEmpty else {
            return
        }

        if let frames = framesForItems(pills.map(\.intrinsicContentSize)) {
            apply(frames: frames, visiblePillCount: pills.count)
            hiddenSpaceIDs = []
            return
        }

        for visibleCount in stride(from: pills.count - 1, through: 0, by: -1) {
            let hiddenCount = pills.count - visibleCount
            overflowPill.title = "+\(hiddenCount)"
            let sizes = Array(pills.prefix(visibleCount).map(\.intrinsicContentSize))
                + [overflowPill.intrinsicContentSize]
            guard let frames = framesForItems(sizes) else {
                continue
            }
            apply(frames: Array(frames.dropLast()), visiblePillCount: visibleCount)
            hiddenSpaceIDs = Array(spaceIDs.dropFirst(visibleCount))
            overflowPill.frame = frames[frames.count - 1]
            overflowPill.isHidden = false
            return
        }

        pills.forEach { $0.isHidden = true }
        hiddenSpaceIDs = spaceIDs
        overflowPill.title = "+\(spaceIDs.count)"
        overflowPill.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: min(overflowPill.intrinsicContentSize.width, bounds.width),
                height: min(overflowPill.intrinsicContentSize.height, bounds.height)
            )
        )
        overflowPill.isHidden = false
    }

    private var hiddenSpaceIDs: [SpaceID] = []

    private func apply(frames: [NSRect], visiblePillCount: Int) {
        for (index, pill) in pills.enumerated() {
            pill.isHidden = index >= visiblePillCount
            if index < visiblePillCount {
                pill.frame = frames[index]
            }
        }
    }

    private func framesForItems(_ sizes: [NSSize]) -> [NSRect]? {
        let spacing: CGFloat = 5
        var frames: [NSRect] = []
        var origin = NSPoint.zero
        var rowHeight: CGFloat = 0

        for originalSize in sizes {
            let size = NSSize(width: min(originalSize.width, bounds.width), height: originalSize.height)
            if origin.x > 0, origin.x + size.width > bounds.width {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            guard origin.y + size.height <= bounds.height else {
                return nil
            }
            frames.append(NSRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return frames
    }
}

private final class SpacePillView: NSView, NSDraggingSource {
    let spaceID: SpaceID
    var onSelect: ((SpaceID) -> Void)?

    private let label: NSTextField
    private let isSelected: Bool
    private var didStartDragging = false

    init(spaceID: SpaceID, isSelected: Bool) {
        self.spaceID = spaceID
        self.isSelected = isSelected
        label = NSTextField(labelWithString: spaceID.rawValue)
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityIdentifier("cosmos.settings.space-pill.\(spaceID.rawValue)")
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

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlAccentColor
            .withAlphaComponent(isSelected ? 0.38 : 0.18)
            .cgColor
        layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isSelected ? 1 : 0
        layer?.cornerRadius = 6
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with _: NSEvent) {
        didStartDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDragging else {
            return
        }
        didStartDragging = true
        let draggingItem = NSDraggingItem(
            pasteboardWriter: SpaceDragPayload.pasteboardItem(for: spaceID)
        )
        draggingItem.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with _: NSEvent) {
        if !didStartDragging {
            onSelect?(spaceID)
        }
    }

    func draggingSession(
        _: NSDraggingSession,
        sourceOperationMaskFor _: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    private func dragImage() -> NSImage {
        guard let representation = bitmapImageRepForCachingDisplay(in: bounds) else {
            return NSImage(size: bounds.size)
        }
        cacheDisplay(in: bounds, to: representation)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(representation)
        return image
    }
}

private final class SpaceOverflowPillView: NSButton {
    var onSelect: ((NSView) -> Void)?

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(38, super.intrinsicContentSize.width + 10), height: 24)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        font = .systemFont(ofSize: 11, weight: .semibold)
        target = self
        action = #selector(selectOverflow)
        setAccessibilityIdentifier("cosmos.settings.space-overflow")
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
        layer?.cornerRadius = 6
    }

    @objc private func selectOverflow() {
        onSelect?(self)
    }
}

private final class SpaceOverflowViewController: NSViewController {
    let popoverContentSize: NSSize

    init(
        spaceIDs: [SpaceID],
        onSpaceSelected: @escaping (SpaceID) -> Void
    ) {
        let columns = 6
        let spaceRows = stride(from: 0, to: spaceIDs.count, by: columns).map { start in
            Array(spaceIDs[start ..< min(start + columns, spaceIDs.count)])
        }
        let rows = spaceRows.map { rowIDs in
            let pills = rowIDs.map { spaceID in
                let pill = SpacePillView(spaceID: spaceID, isSelected: false)
                pill.onSelect = onSpaceSelected
                return pill
            }
            let row = NSStackView(views: pills)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 12
        popoverContentSize = NSSize(
            width: max(220, stack.fittingSize.width + horizontalPadding * 2),
            height: max(44, stack.fittingSize.height + verticalPadding * 2)
        )
        super.init(nibName: nil, bundle: nil)
        let container = NSView(frame: NSRect(origin: .zero, size: popoverContentSize))
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalPadding),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalPadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalPadding),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalPadding)
        ])
        view = container
        view.setAccessibilityIdentifier("cosmos.settings.space-overflow-popover")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ParkingWarningViewController: NSViewController {
    let popoverContentSize: NSSize
    private let detailsURL: String

    init(message: String, detailsURL: String) {
        self.detailsURL = detailsURL

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 12)
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping

        let detailsButton = NSButton(title: "See details", target: nil, action: nil)
        detailsButton.isBordered = false
        detailsButton.contentTintColor = .linkColor

        let content = NSStackView(views: [messageLabel, detailsButton])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false

        popoverContentSize = NSSize(width: 360, height: 116)
        super.init(nibName: nil, bundle: nil)
        detailsButton.target = self
        detailsButton.action = #selector(openDetails)
        let container = NSView(frame: NSRect(origin: .zero, size: popoverContentSize))
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12),
            messageLabel.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        view = container
        view.setAccessibilityIdentifier("cosmos.settings.display-parking-popover")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func openDetails() {
        guard let url = URL(string: detailsURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
