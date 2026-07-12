import AppKit
import KkaciCore

final class SwitcherOverlayViewFactory {
    private let rootView = SwitcherOverlayRootView()
    private let windowListView = WindowSwitcherListView(frame: .zero)
    private let workspaceListView = WorkspaceSwitcherListView(frame: .zero)

    var rootContentView: NSView {
        rootView
    }

    func prepare(windowCount: Int, workspaceCount: Int) {
        windowListView.ensureCapacity(windowCount)
        workspaceListView.ensureCapacity(workspaceCount)
    }

    func makeRootContent(title: String?, content: NSView) -> NSView {
        rootView.configure(title: title, content: content)
        return rootView
    }

    func makeWindowList(
        items: [WindowSwitcherItem],
        selectedID: WindowID,
        availableFrame: NSRect,
        onHover: ((WindowID) -> Void)? = nil,
        onClick: ((WindowID) -> Void)? = nil
    ) -> WindowSwitcherListView {
        windowListView.configure(
            items: items,
            selectedID: selectedID,
            metrics: tileMetrics(count: items.count, availableFrame: availableFrame),
            onHover: onHover,
            onClick: onClick
        )
        return windowListView
    }

    func makeWorkspaceList(
        groups: [WorkspaceSwitcherGroup],
        selectedName: String,
        availableFrame: NSRect,
        onHover: @escaping (String) -> Void,
        onClick: @escaping (String) -> Void
    ) -> WorkspaceSwitcherListView {
        workspaceListView.configure(
            groups: groups,
            selectedName: selectedName,
            availableFrame: availableFrame,
            onHover: onHover,
            onClick: onClick
        )
        return workspaceListView
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

private final class SwitcherOverlayRootView: NSView {
    private let backgroundView = NSVisualEffectView()
    private let titleLabel = NSTextField(labelWithString: "")
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

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String?, content: NSView) {
        let horizontalPadding: CGFloat = 20
        let verticalPadding: CGFloat = 18
        let titleSpacing: CGFloat = title == nil ? 0 : 12
        let titleHeight: CGFloat = title == nil ? 0 : 22
        let rootSize = NSSize(
            width: content.frame.width + horizontalPadding * 2,
            height: content.frame.height + verticalPadding * 2 + titleSpacing + titleHeight
        )

        frame.size = rootSize
        backgroundView.frame = bounds
        titleLabel.stringValue = title ?? ""
        titleLabel.isHidden = title == nil
        titleLabel.frame = NSRect(
            x: horizontalPadding,
            y: verticalPadding + content.frame.height + titleSpacing,
            width: content.frame.width,
            height: titleHeight
        )

        if currentContent !== content {
            currentContent?.removeFromSuperview()
            currentContent = content
            addSubview(content)
        }
        content.frame.origin = NSPoint(x: horizontalPadding, y: verticalPadding)
    }
}

final class SwitcherHoverGate {
    private let initialLocation = NSEvent.mouseLocation
    private var isEnabled = false

    func allowHoverIfPointerMoved() -> Bool {
        if isEnabled {
            return true
        }

        let location = NSEvent.mouseLocation
        if abs(location.x - initialLocation.x) >= 1 || abs(location.y - initialLocation.y) >= 1 {
            isEnabled = true
        }
        return isEnabled
    }
}
