import AppKit

struct WorkspaceApplicationIconLayout {
    private static let maximumWidthRatio: CGFloat = 0.70
    private static let iconHeightRatio: CGFloat = 0.20
    private static let iconWidthRatio: CGFloat = 0.12
    private static let spacingRatio: CGFloat = 0.16

    let iconFrames: [NSRect]
    let overflowFrame: NSRect?
    let overflowCount: Int
    let columns: Int

    init(bounds: NSRect, applicationCount: Int) {
        guard applicationCount > 0, bounds.width > 0, bounds.height > 0 else {
            iconFrames = []
            overflowFrame = nil
            overflowCount = 0
            columns = 0
            return
        }

        let maximumWidth = bounds.width * Self.maximumWidthRatio
        let preferredIconSize = max(
            20,
            min(bounds.height * Self.iconHeightRatio, bounds.width * Self.iconWidthRatio)
        )
        let iconSize = min(preferredIconSize, min(maximumWidth, bounds.height))
        let spacing = iconSize * Self.spacingRatio
        columns = max(1, Int((maximumWidth + spacing) / (iconSize + spacing)))
        let twoRowsHeight = iconSize * 2 + spacing
        let maximumRows = twoRowsHeight <= bounds.height ? 2 : 1
        let capacity = columns * maximumRows
        let visibleIconCount = applicationCount <= capacity
            ? applicationCount
            : max(0, capacity - 1)
        overflowCount = applicationCount - visibleIconCount

        let slotCount = visibleIconCount + (overflowCount > 0 ? 1 : 0)
        let rows = Int(ceil(Double(slotCount) / Double(columns)))
        let gridHeight = CGFloat(rows) * iconSize + CGFloat(max(rows - 1, 0)) * spacing
        let originY = bounds.midY - gridHeight / 2

        var frames: [NSRect] = []
        for row in 0 ..< rows {
            let firstSlot = row * columns
            let slotsInRow = min(columns, slotCount - firstSlot)
            let rowWidth = CGFloat(slotsInRow) * iconSize
                + CGFloat(max(slotsInRow - 1, 0)) * spacing
            let originX = bounds.midX - rowWidth / 2
            let rowY = originY + CGFloat(rows - row - 1) * (iconSize + spacing)

            for column in 0 ..< slotsInRow {
                frames.append(NSRect(
                    x: originX + CGFloat(column) * (iconSize + spacing),
                    y: rowY,
                    width: iconSize,
                    height: iconSize
                ))
            }
        }

        iconFrames = Array(frames.prefix(visibleIconCount))
        overflowFrame = overflowCount > 0 ? frames.last : nil
    }
}

final class WorkspaceApplicationIconStripView: NSView {
    private var applications: [WindowSwitcherItem] = []
    private var iconViews: [NSImageView] = []
    private let overflowView = WorkspaceApplicationOverflowView()
    private var isContentVisible = false

    var hasVisibleIcon: Bool {
        isContentVisible && applications.contains { $0.icon != nil }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        overflowView.isHidden = true
        addSubview(overflowView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()

        let layout = WorkspaceApplicationIconLayout(
            bounds: bounds,
            applicationCount: isContentVisible ? applications.count : 0
        )
        ensureIconViewCount(layout.iconFrames.count)

        for (index, imageView) in iconViews.enumerated() {
            guard index < layout.iconFrames.count else {
                imageView.image = nil
                imageView.isHidden = true
                continue
            }
            imageView.frame = layout.iconFrames[index]
            imageView.image = applications[index].icon
            imageView.isHidden = imageView.image == nil
        }

        if let overflowFrame = layout.overflowFrame {
            overflowView.frame = overflowFrame
            overflowView.update(count: layout.overflowCount)
            overflowView.isHidden = false
        } else {
            overflowView.isHidden = true
        }
    }

    func update(windows: [WindowSwitcherItem], isVisible: Bool) {
        var seenAppNames: Set<String> = []
        applications = windows.filter { seenAppNames.insert($0.appName).inserted }
        isContentVisible = isVisible
        needsLayout = true
    }

    private func ensureIconViewCount(_ count: Int) {
        while iconViews.count < count {
            let imageView = NSImageView()
            imageView.imageScaling = .scaleProportionallyUpOrDown
            iconViews.append(imageView)
            addSubview(imageView, positioned: .below, relativeTo: overflowView)
        }
    }
}

private final class WorkspaceApplicationOverflowView: NSView {
    private static let boxScale: CGFloat = 0.86

    private let boxView = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        boxView.wantsLayer = true
        boxView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        boxView.layer?.borderWidth = 1
        boxView.layer?.borderColor = NSColor.white.withAlphaComponent(0.28).cgColor
        label.alignment = .center
        label.textColor = NSColor.white.withAlphaComponent(0.85)
        boxView.addSubview(label)
        addSubview(boxView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let inset = bounds.width * (1 - Self.boxScale) / 2
        boxView.frame = bounds.insetBy(dx: inset, dy: inset)
        boxView.layer?.cornerRadius = boxView.bounds.width * 0.22
        label.font = .systemFont(ofSize: boxView.bounds.height * 0.34, weight: .semibold)
        label.sizeToFit()
        label.frame.origin = NSPoint(
            x: floor(boxView.bounds.midX - label.frame.width / 2),
            y: floor(boxView.bounds.midY - label.frame.height / 2)
        )
    }

    func update(count: Int) {
        label.stringValue = "+\(count)"
        needsLayout = true
    }
}
