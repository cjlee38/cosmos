import AppKit
import KkaciCore

final class WorkspaceSwitcherListView: NSView {
    private var previewViewsByID: [WindowID: [WorkspaceWindowPreviewView]] = [:]

    init(groups: [WorkspaceSwitcherGroup], selectedIndex: Int, availableFrame: NSRect) {
        let layout = WorkspaceOverviewLayout(groupCount: groups.count, availableFrame: availableFrame)
        super.init(frame: NSRect(origin: .zero, size: layout.contentSize))
        setup(groups: groups, selectedIndex: selectedIndex, availableFrame: availableFrame, layout: layout)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreviews(groups: [WorkspaceSwitcherGroup]) {
        for item in groups.flatMap(\.windows) {
            previewViewsByID[item.id]?.forEach { $0.updatePreview(item) }
        }
    }

    private func setup(
        groups: [WorkspaceSwitcherGroup],
        selectedIndex: Int,
        availableFrame: NSRect,
        layout: WorkspaceOverviewLayout
    ) {
        for (index, group) in groups.enumerated() {
            let row = index / layout.columns
            let column = index % layout.columns
            let cell = layout.cellFrame(row: row, column: column)
            let card = WorkspacePreviewCardView(
                group: group,
                isSelected: index == selectedIndex,
                cardSize: layout.cardSize,
                desktopBounds: desktopBounds(for: group, fallback: availableFrame)
            )
            card.frame.origin = NSPoint(
                x: cell.midX - layout.cardSize.width / 2,
                y: cell.midY - layout.cardSize.height / 2
            )
            addSubview(card)
            merge(card.previewViewsByID)
        }
    }

    private func desktopBounds(for group: WorkspaceSwitcherGroup, fallback: NSRect) -> CGRect {
        let fallbackBounds = CGRect(x: fallback.minX, y: fallback.minY, width: fallback.width, height: fallback.height)
        return group.windows
            .compactMap(\.frame)
            .map { CGRect(origin: $0.origin, size: $0.size) }
            .reduce(fallbackBounds) { $0.union($1) }
    }

    private func merge(_ source: [WindowID: [WorkspaceWindowPreviewView]]) {
        for (id, views) in source {
            previewViewsByID[id, default: []].append(contentsOf: views)
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
        let chromeHeight: CGFloat = 62
        let horizontalChrome: CGFloat = 24
        let maxCanvasWidth = max(160, cellWidth - horizontalChrome)
        let maxCanvasHeight = max(100, cellHeight - chromeHeight)
        let canvasWidth = min(maxCanvasWidth, maxCanvasHeight * screenAspect)
        let canvasHeight = canvasWidth / screenAspect

        self.contentSize = contentSize
        self.cardSize = NSSize(width: canvasWidth + horizontalChrome, height: canvasHeight + chromeHeight)
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
        case 2...3:
            groupCount
        case 4:
            2
        case 5...6:
            3
        default:
            Int(ceil(sqrt(Double(groupCount))))
        }
    }
}

private final class WorkspacePreviewCardView: NSView {
    private(set) var previewViewsByID: [WindowID: [WorkspaceWindowPreviewView]] = [:]

    init(group: WorkspaceSwitcherGroup, isSelected: Bool, cardSize: NSSize, desktopBounds: CGRect) {
        super.init(frame: NSRect(origin: .zero, size: cardSize))
        setupChrome(isSelected: isSelected)
        setupContent(group: group, desktopBounds: desktopBounds)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupChrome(isSelected: Bool) {
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.20).cgColor
            : NSColor.black.withAlphaComponent(0.28).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isSelected ? 0.36 : 0.22
        layer?.shadowRadius = isSelected ? 18 : 12
        layer?.shadowOffset = NSSize(width: 0, height: -4)
    }

    private func setupContent(group: WorkspaceSwitcherGroup, desktopBounds: CGRect) {
        let padding: CGFloat = 12
        let titleHeight: CGFloat = 22
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

        let canvasFrame = NSRect(
            x: padding,
            y: padding,
            width: bounds.width - padding * 2,
            height: title.frame.minY - padding * 1.35
        )
        let canvas = WorkspaceDesktopCanvasView(
            frame: canvasFrame,
            windows: group.windows,
            desktopBounds: desktopBounds
        )

        addSubview(canvas)
        addSubview(title)
        previewViewsByID = canvas.previewViewsByID
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

private final class WorkspaceDesktopCanvasView: NSView {
    private(set) var previewViewsByID: [WindowID: [WorkspaceWindowPreviewView]] = [:]

    init(frame: NSRect, windows: [WindowSwitcherItem], desktopBounds: CGRect) {
        super.init(frame: frame)
        setupSurface()
        addWindowPreviews(windows, desktopBounds: desktopBounds)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupSurface() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.36).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
    }

    private func addWindowPreviews(_ windows: [WindowSwitcherItem], desktopBounds: CGRect) {
        let positionedWindows = windows.compactMap { item -> (WindowSwitcherItem, WindowFrame)? in
            item.frame.map { (item, $0) }
        }

        for (item, frame) in positionedWindows {
            let preview = WorkspaceWindowPreviewView(item: item)
            preview.frame = previewFrame(for: frame, desktopBounds: desktopBounds)
            addSubview(preview)
            previewViewsByID[item.id, default: []].append(preview)
        }
    }

    private func previewFrame(for frame: WindowFrame, desktopBounds: CGRect) -> NSRect {
        let drawingBounds = bounds.insetBy(dx: 10, dy: 10)
        let desktopWidth = max(desktopBounds.width, 1)
        let desktopHeight = max(desktopBounds.height, 1)
        let scale = min(drawingBounds.width / desktopWidth, drawingBounds.height / desktopHeight)
        let usedSize = NSSize(width: desktopWidth * scale, height: desktopHeight * scale)
        let origin = NSPoint(
            x: drawingBounds.midX - usedSize.width / 2,
            y: drawingBounds.midY - usedSize.height / 2
        )
        let width = max(28, frame.size.width * scale)
        let height = max(20, frame.size.height * scale)
        let x = origin.x + (frame.origin.x - desktopBounds.minX) * scale
        let yFromTop = (frame.origin.y - desktopBounds.minY) * scale
        let y = origin.y + usedSize.height - yFromTop - height

        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class WorkspaceWindowPreviewView: NSView {
    private let previewImageView = NSImageView()
    private let fallbackIconView = NSImageView()
    private let fallbackInitialLabel = NSTextField(labelWithString: "")

    init(item: WindowSwitcherItem) {
        super.init(frame: .zero)
        setup()
        updatePreview(item)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreview(_ item: WindowSwitcherItem) {
        previewImageView.image = item.preview
        previewImageView.isHidden = item.preview == nil

        fallbackIconView.image = item.icon
        fallbackIconView.isHidden = item.preview != nil || item.icon == nil

        fallbackInitialLabel.stringValue = item.appName.first.map(String.init) ?? "?"
        fallbackInitialLabel.isHidden = item.preview != nil || item.icon != nil
    }

    override func layout() {
        super.layout()
        previewImageView.frame = bounds
        fallbackIconView.frame = bounds.insetBy(dx: bounds.width * 0.30, dy: bounds.height * 0.30)
        fallbackInitialLabel.frame = bounds
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.42).cgColor

        previewImageView.imageScaling = .scaleAxesIndependently
        fallbackIconView.imageScaling = .scaleProportionallyUpOrDown
        fallbackInitialLabel.alignment = .center
        fallbackInitialLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        fallbackInitialLabel.textColor = .white

        addSubview(previewImageView)
        addSubview(fallbackIconView)
        addSubview(fallbackInitialLabel)
    }
}
