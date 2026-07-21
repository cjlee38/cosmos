import AppKit
import KkaciCore

enum WorkspaceDragPayload {
    static let pasteboardType = NSPasteboard.PasteboardType("dev.kkaci.workspace-id")

    static func pasteboardItem(for workspaceID: WorkspaceID) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(workspaceID.rawValue, forType: pasteboardType)
        return item
    }

    static func workspaceID(from pasteboard: NSPasteboard) -> WorkspaceID? {
        pasteboard.string(forType: pasteboardType).flatMap(WorkspaceID.init(rawValue:))
    }
}

final class WorkspaceDisplayArrangementView: NSView {
    var onDisplaySelected: ((DisplayID) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onWorkspaceSelected: ((WorkspaceID) -> Void)?
    var onWorkspaceMoved: ((WorkspaceID, DisplayID) -> Void)?

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

    override func mouseDown(with _: NSEvent) {
        onSelectionCleared?()
    }

    func apply(
        _ displays: [WorkspaceSettingsDisplay],
        selectedDisplayID: DisplayID?,
        selectedWorkspaceID: WorkspaceID?,
        isEditable: Bool
    ) {
        for displayCard in displayCards {
            displayCard.view.removeFromSuperview()
        }

        displayCards = displays.map { item in
            let card = WorkspaceDisplayCardView(
                item: item,
                isSelected: item.id == selectedDisplayID,
                selectedWorkspaceID: selectedWorkspaceID,
                isEditable: isEditable
            )
            card.onSelect = { [weak self] in self?.onDisplaySelected?(item.id) }
            card.onWorkspaceSelected = { [weak self] workspaceID in
                self?.onWorkspaceSelected?(workspaceID)
            }
            card.onWorkspaceMoved = { [weak self] workspaceID in
                self?.onWorkspaceMoved?(workspaceID, item.id)
            }
            card.onOverflowSelected = { [weak self] in self?.onDisplaySelected?(item.id) }
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
    var onSelect: (() -> Void)?
    var onWorkspaceSelected: ((WorkspaceID) -> Void)?
    var onWorkspaceMoved: ((WorkspaceID) -> Void)?
    var onOverflowSelected: (() -> Void)?

    private let isSelected: Bool
    private let isEditable: Bool
    private var isDropTarget = false
    private let workspaceFlow: WorkspacePillFlowView

    init(
        item: WorkspaceSettingsDisplay,
        isSelected: Bool,
        selectedWorkspaceID: WorkspaceID?,
        isEditable: Bool
    ) {
        self.isSelected = isSelected
        self.isEditable = isEditable
        workspaceFlow = WorkspacePillFlowView(
            workspaceIDs: item.workspaceIDs,
            selectedWorkspaceID: selectedWorkspaceID
        )
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityIdentifier("kkaci.settings.display.\(item.monitorSlot)")
        registerForDraggedTypes([WorkspaceDragPayload.pasteboardType])

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
        workspaceFlow.onWorkspaceSelected = { [weak self] workspaceID in
            self?.onWorkspaceSelected?(workspaceID)
        }
        workspaceFlow.onOverflowSelected = { [weak self] in self?.onOverflowSelected?() }

        addSubview(heading)
        addSubview(workspaceFlow)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -11),
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
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = isSelected || isDropTarget ? 2 : 1
        layer?.cornerRadius = 7
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hitView = super.hitTest(point) else {
            return nil
        }
        if hitView is NSButton || hitView is WorkspacePillView {
            return hitView
        }
        return self
    }

    override func mouseDown(with _: NSEvent) {
        onSelect?()
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard isEditable,
              WorkspaceDragPayload.workspaceID(from: sender.draggingPasteboard) != nil
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
              let workspaceID = WorkspaceDragPayload.workspaceID(from: sender.draggingPasteboard)
        else {
            return false
        }
        onWorkspaceMoved?(workspaceID)
        return true
    }

    private var borderColor: NSColor {
        isSelected || isDropTarget ? .controlAccentColor : .separatorColor
    }
}

private final class WorkspacePillFlowView: NSView {
    var onWorkspaceSelected: ((WorkspaceID) -> Void)?
    var onOverflowSelected: (() -> Void)?

    private let workspaceIDs: [WorkspaceID]
    private var pills: [WorkspacePillView] = []
    private let overflowPill = WorkspaceOverflowPillView()
    private let emptyLabel = NSTextField(labelWithString: "No workspaces")

    init(workspaceIDs: [WorkspaceID], selectedWorkspaceID: WorkspaceID?) {
        self.workspaceIDs = workspaceIDs
        super.init(frame: .zero)
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = .tertiaryLabelColor
        addSubview(emptyLabel)
        addSubview(overflowPill)
        overflowPill.onSelect = { [weak self] in self?.onOverflowSelected?() }

        pills = workspaceIDs.map { workspaceID in
            let pill = WorkspacePillView(
                workspaceID: workspaceID,
                isSelected: workspaceID == selectedWorkspaceID
            )
            pill.onSelect = { [weak self] id in self?.onWorkspaceSelected?(id) }
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
            overflowPill.frame = frames[frames.count - 1]
            overflowPill.isHidden = false
            return
        }

        pills.forEach { $0.isHidden = true }
    }

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

private final class WorkspacePillView: NSView, NSDraggingSource {
    let workspaceID: WorkspaceID
    var onSelect: ((WorkspaceID) -> Void)?

    private let label: NSTextField
    private let isSelected: Bool
    private var didStartDragging = false

    init(workspaceID: WorkspaceID, isSelected: Bool) {
        self.workspaceID = workspaceID
        self.isSelected = isSelected
        label = NSTextField(labelWithString: workspaceID.rawValue)
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityIdentifier("kkaci.settings.workspace-pill.\(workspaceID.rawValue)")
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
            pasteboardWriter: WorkspaceDragPayload.pasteboardItem(for: workspaceID)
        )
        draggingItem.setDraggingFrame(bounds, contents: dragImage())
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with _: NSEvent) {
        if !didStartDragging {
            onSelect?(workspaceID)
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

private final class WorkspaceOverflowPillView: NSButton {
    var onSelect: (() -> Void)?

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
        setAccessibilityIdentifier("kkaci.settings.workspace-overflow")
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
        onSelect?()
    }
}
