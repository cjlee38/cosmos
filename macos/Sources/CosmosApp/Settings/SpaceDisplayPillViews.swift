import AppKit
import CosmosCore

final class SpacePillFlowView: NSView {
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
        panic("init(coder:) has not been implemented")
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

final class SpacePillView: NSView, NSDraggingSource {
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
        panic("init(coder:) has not been implemented")
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
        panic("init(coder:) has not been implemented")
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

final class SpaceOverflowViewController: NSViewController {
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
        panic("init(coder:) has not been implemented")
    }
}

final class ParkingWarningViewController: NSViewController {
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
        panic("init(coder:) has not been implemented")
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
