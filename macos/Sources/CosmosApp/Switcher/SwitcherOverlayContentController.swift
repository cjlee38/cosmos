import AppKit
import CosmosCore

final class SwitcherOverlayContentController {
    private let appSettingsStore: AppSettingsStore
    private let rootView = SwitcherOverlayRootView()
    private let windowListView = WindowSwitcherListView(frame: .zero)
    private let spaceListView = SpaceSwitcherListView(frame: .zero)

    init(appSettingsStore: AppSettingsStore) {
        self.appSettingsStore = appSettingsStore
    }

    var rootContentView: NSView {
        rootView
    }

    func beginWindowPresentation() {
        windowListView.beginPresentation()
    }

    func beginSpacePresentation() {
        spaceListView.beginPresentation()
    }

    func configureRootContent(_ content: NSView) -> NSView {
        rootView.configure(content: content)
        return rootView
    }

    func configureWindowList(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        availableFrame: NSRect,
        onHover: ((WindowID) -> Void)? = nil,
        onClick: ((WindowID) -> Void)? = nil
    ) -> WindowSwitcherListView {
        let settings = appSettingsStore.snapshot()
        windowListView.configure(
            items: items,
            selectedID: selectedID,
            metrics: tileMetrics(
                count: items.count,
                availableFrame: availableFrame,
                scale: CGFloat(settings.windowSwitcherSize)
            ),
            onHover: onHover,
            onClick: onClick
        )
        return windowListView
    }

    func configureSpaceList(
        groups: [SpaceSwitcherGroup],
        selectedID: String,
        availableFrame: NSRect,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) -> SpaceSwitcherListView {
        let settings = appSettingsStore.snapshot()
        spaceListView.configure(
            groups: groups,
            selectedID: selectedID,
            availableFrame: availableFrame,
            size: CGFloat(settings.spaceSwitcherSize),
            interactions: SpaceSwitcherInteractions(onHover: onHover, onClick: onClick)
        )
        return spaceListView
    }

    func updateWindowPreviews(_ items: [WindowSwitcherItem]) {
        windowListView.updatePreviews(items: items)
    }

    func updateWindowSelection(_ selectedID: WindowID) {
        windowListView.updateSelection(selectedID: selectedID)
    }

    func updateSpacePreviews(_ groups: [SpaceSwitcherGroup]) {
        spaceListView.updatePreviews(groups: groups)
    }

    func updateSpaceSelection(_ selectedID: String) {
        spaceListView.updateSelection(selectedID: selectedID)
    }

    private func tileMetrics(
        count: Int,
        availableFrame: NSRect,
        scale: CGFloat
    ) -> WindowTileMetrics {
        let spacing = floor(10 * scale)
        let targetWidth = floor(targetTileWidth(count: count) * scale)
        let minimumWidth: CGFloat = 80
        let maxContentWidth = max(minimumWidth, availableFrame.width * 0.86)
        let maxContentHeight = max(100, availableFrame.height * 0.82)
        let itemCount = max(count, 1)
        let minimumPreferredWidth = targetWidth * 0.9
        let preferredMaximumColumns = max(
            1,
            min(
                itemCount,
                Int((maxContentWidth + spacing) / (minimumPreferredWidth + spacing))
            )
        )
        let desiredColumns = balancedColumnCount(
            itemCount: itemCount,
            maximumColumns: preferredMaximumColumns
        )
        let maximumColumns = max(
            desiredColumns,
            min(
                itemCount,
                Int((maxContentWidth + spacing) / (minimumWidth + spacing))
            )
        )

        var fallback = metrics(
            itemCount: itemCount,
            columns: desiredColumns,
            spacing: spacing,
            targetWidth: targetWidth,
            maxContentWidth: maxContentWidth
        )
        for columns in desiredColumns ... maximumColumns {
            let candidate = metrics(
                itemCount: itemCount,
                columns: columns,
                spacing: spacing,
                targetWidth: targetWidth,
                maxContentWidth: maxContentWidth
            )
            fallback = candidate
            if candidate.contentHeight <= maxContentHeight {
                return candidate
            }
        }
        return fallback
    }

    private func balancedColumnCount(itemCount: Int, maximumColumns: Int) -> Int {
        let minimumColumns = max(1, Int(ceil(Double(maximumColumns) / 2)))
        return (minimumColumns ... maximumColumns).min { lhs, rhs in
            let lhsScore = gridScore(itemCount: itemCount, columns: lhs)
            let rhsScore = gridScore(itemCount: itemCount, columns: rhs)
            return lhsScore == rhsScore ? lhs > rhs : lhsScore < rhsScore
        } ?? maximumColumns
    }

    private func gridScore(itemCount: Int, columns: Int) -> Int {
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let unusedCells = rows * columns - itemCount
        return unusedCells + rows
    }

    private func metrics(
        itemCount: Int,
        columns: Int,
        spacing: CGFloat,
        targetWidth: CGFloat,
        maxContentWidth: CGFloat
    ) -> WindowTileMetrics {
        let widthThatFits =
            (maxContentWidth - CGFloat(max(columns - 1, 0)) * spacing) / CGFloat(columns)
        let tileWidth = min(targetWidth, floor(widthThatFits))
        let rows = Int(ceil(Double(itemCount) / Double(columns)))
        let previewHeight = max(52, floor(tileWidth * 0.62))
        let labelHeight: CGFloat = tileWidth < 120 ? 50 : 57
        let tileHeight = previewHeight + labelHeight
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
            280
        case 2:
            240
        case 3:
            210
        case 4:
            185
        default:
            168
        }
    }
}

struct SpaceOverviewLayout {
    private struct Dimensions {
        let widthRatio: CGFloat
        let heightRatio: CGFloat
        let spacing: CGFloat
    }

    let contentSize: NSSize
    let cardSize: NSSize
    let columns: Int
    private let rows: Int
    private let spacing: CGFloat

    init(groupCount: Int, availableFrame: NSRect, size: CGFloat) {
        let count = max(groupCount, 1)
        let dimensions = Self.dimensions(for: size)
        let spacing = dimensions.spacing
        let columns = Self.columnCount(groupCount: count)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let maximumContentSize = NSSize(
            width: floor(availableFrame.width * dimensions.widthRatio),
            height: floor(availableFrame.height * dimensions.heightRatio)
        )
        let cellWidth = (maximumContentSize.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let cellHeight = (maximumContentSize.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
        let cardAspect: CGFloat = 1.45
        let cardWidth = min(cellWidth, cellHeight * cardAspect)
        let cardHeight = min(cellHeight, cardWidth / cardAspect)
        let contentSize = NSSize(
            width: CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing,
            height: CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing
        )

        self.contentSize = NSSize(width: floor(contentSize.width), height: floor(contentSize.height))
        cardSize = NSSize(width: floor(cardWidth), height: floor(cardHeight))
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

    private static func dimensions(for size: CGFloat) -> Dimensions {
        let small = Dimensions(widthRatio: 0.52, heightRatio: 0.48, spacing: 12)
        let medium = Dimensions(widthRatio: 0.72, heightRatio: 0.66, spacing: 18)
        let large = Dimensions(widthRatio: 0.965, heightRatio: 0.94, spacing: 30)
        if size <= 0.5 {
            return interpolate(from: small, to: medium, progress: size * 2)
        }
        return interpolate(from: medium, to: large, progress: (size - 0.5) * 2)
    }

    private static func interpolate(
        from start: Dimensions,
        to end: Dimensions,
        progress: CGFloat
    ) -> Dimensions {
        Dimensions(
            widthRatio: start.widthRatio + (end.widthRatio - start.widthRatio) * progress,
            heightRatio: start.heightRatio + (end.heightRatio - start.heightRatio) * progress,
            spacing: start.spacing + (end.spacing - start.spacing) * progress
        )
    }
}

private final class SwitcherOverlayRootView: NSView {
    private let backgroundView = NSVisualEffectView()
    private weak var currentContent: NSView?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        backgroundView.material = .hudWindow
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        backgroundView.alphaValue = 0.89
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        addSubview(backgroundView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        panic("init(coder:) has not been implemented")
    }

    func configure(content: NSView) {
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 18
        let rootSize = NSSize(
            width: content.frame.width + horizontalPadding * 2,
            height: content.frame.height + verticalPadding * 2
        )

        frame.size = rootSize
        backgroundView.frame = bounds

        if currentContent !== content {
            currentContent?.removeFromSuperview()
            currentContent = content
            addSubview(content)
        }
        content.frame.origin = NSPoint(x: horizontalPadding, y: verticalPadding)
    }
}

final class SwitcherHoverGate {
    private let pointerLocation: () -> NSPoint
    private var initialLocation: NSPoint
    private var isEnabled = false

    init(pointerLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
        initialLocation = pointerLocation()
    }

    func reset() {
        initialLocation = pointerLocation()
        isEnabled = false
    }

    func allowHoverIfPointerMoved() -> Bool {
        if isEnabled {
            return true
        }

        let location = pointerLocation()
        if abs(location.x - initialLocation.x) >= 1 || abs(location.y - initialLocation.y) >= 1 {
            isEnabled = true
        }
        return isEnabled
    }
}
