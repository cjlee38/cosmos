import AppKit
import KkaciCore

final class SwitcherOverlayViewFactory {
    func makeRootContent(title: String, content: NSView) -> NSView {
        let root = NSVisualEffectView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true

        let titleLabel = label(title, font: .systemFont(ofSize: 18, weight: .semibold), color: .white)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [titleLabel, content])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16

        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -22),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return root
    }

    func makeWindowList(
        items: [WindowSwitcherItem],
        selectedIndex: Int,
        compact: Bool
    ) -> WindowSwitcherListView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = compact ? 8 : 12
        let tileWidth: CGFloat = compact ? 112 : 176
        let height: CGFloat = compact ? 122 : 318
        var tileViewsByID: [WindowID: [WindowSwitcherTileView]] = [:]

        if items.isEmpty {
            let empty = label("No windows", font: .systemFont(ofSize: 15), color: .secondaryLabelColor)
            empty.frame = NSRect(x: 0, y: 0, width: 180, height: 80)
            stack.addArrangedSubview(empty)
        } else {
            for (index, item) in items.enumerated() {
                let tile = WindowSwitcherTileView(
                    item: item,
                    isSelected: index == selectedIndex,
                    compact: compact
                )
                tileViewsByID[item.id, default: []].append(tile)
                stack.addArrangedSubview(tile)
            }
        }

        let width = items.isEmpty
            ? CGFloat(180)
            : CGFloat(items.count) * tileWidth + CGFloat(max(items.count - 1, 0)) * stack.spacing
        stack.frame = NSRect(x: 0, y: 0, width: width, height: height)

        return WindowSwitcherListView(documentView: stack, tileViewsByID: tileViewsByID)
    }

    func makeWorkspaceList(groups: [WorkspaceSwitcherGroup], selectedIndex: Int) -> WorkspaceSwitcherListView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        var tileViewsByID: [WindowID: [WindowSwitcherTileView]] = [:]

        for (index, group) in groups.enumerated() {
            let rendered = makeWorkspaceGroup(group, isSelected: index == selectedIndex)
            mergeTileViews(rendered.tileViewsByID, into: &tileViewsByID)
            stack.addArrangedSubview(rendered.view)
        }
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(max(groups.count, 1)) * 260 + CGFloat(max(groups.count - 1, 0)) * stack.spacing,
            height: 250
        )

        return WorkspaceSwitcherListView(documentView: stack, tileViewsByID: tileViewsByID)
    }

    private func makeWorkspaceGroup(
        _ group: WorkspaceSwitcherGroup,
        isSelected: Bool
    ) -> (view: NSView, tileViewsByID: [WindowID: [WindowSwitcherTileView]]) {
        let title = label(
            "Workspace \(group.name)",
            font: .systemFont(ofSize: 15, weight: .semibold),
            color: .white
        )

        let windows = makeWindowList(items: group.windows, selectedIndex: -1, compact: true)
        let stack = NSStackView(views: [title, windows])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = isSelected ? 2 : 1
        container.layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.18).cgColor
        container.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.black.withAlphaComponent(0.22).cgColor

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 260),
            container.heightAnchor.constraint(equalToConstant: 250),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12),
            windows.widthAnchor.constraint(equalToConstant: 236),
            windows.heightAnchor.constraint(equalToConstant: 122),
        ])

        return (container, windows.tileViewsByID)
    }

    private func mergeTileViews(
        _ source: [WindowID: [WindowSwitcherTileView]],
        into destination: inout [WindowID: [WindowSwitcherTileView]]
    ) {
        for (id, views) in source {
            destination[id, default: []].append(contentsOf: views)
        }
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        return field
    }
}

final class WindowSwitcherListView: NSScrollView {
    let tileViewsByID: [WindowID: [WindowSwitcherTileView]]

    init(documentView: NSView, tileViewsByID: [WindowID: [WindowSwitcherTileView]]) {
        self.tileViewsByID = tileViewsByID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        self.documentView = documentView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreviews(items: [WindowSwitcherItem]) {
        for item in items {
            tileViewsByID[item.id]?.forEach { $0.updatePreview(item) }
        }
    }
}

final class WorkspaceSwitcherListView: NSScrollView {
    private let tileViewsByID: [WindowID: [WindowSwitcherTileView]]

    init(documentView: NSView, tileViewsByID: [WindowID: [WindowSwitcherTileView]]) {
        self.tileViewsByID = tileViewsByID
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        drawsBackground = false
        self.documentView = documentView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePreviews(groups: [WorkspaceSwitcherGroup]) {
        for item in groups.flatMap(\.windows) {
            tileViewsByID[item.id]?.forEach { $0.updatePreview(item) }
        }
    }
}

final class WindowSwitcherTileView: NSView {
    private let previewImageView = NSImageView()
    private let fallbackIconView = NSImageView()
    private let fallbackInitialLabel = NSTextField(labelWithString: "")

    init(item: WindowSwitcherItem, isSelected: Bool, compact: Bool) {
        super.init(frame: .zero)
        setup(item: item, isSelected: isSelected, compact: compact)
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

    private func setup(item: WindowSwitcherItem, isSelected: Bool, compact: Bool) {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = isSelected ? 2 : 1
        layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            : NSColor.black.withAlphaComponent(0.2).cgColor

        let preview = makePreviewContainer()
        let appLabel = label(
            item.appName,
            font: .systemFont(ofSize: compact ? 11 : 12, weight: .semibold),
            color: .white
        )
        let titleLabel = label(
            item.displayTitle,
            font: .systemFont(ofSize: compact ? 10 : 12),
            color: .secondaryLabelColor
        )
        appLabel.lineBreakMode = .byTruncatingTail
        titleLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [preview, appLabel, titleLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = compact ? 5 : 8

        addSubview(stack)

        let tileWidth: CGFloat = compact ? 112 : 176
        let previewHeight: CGFloat = compact ? 68 : 108
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: tileWidth),
            heightAnchor.constraint(equalToConstant: compact ? 116 : 192),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: compact ? 8 : 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 8 : 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: compact ? -8 : -10),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: previewHeight),
            appLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func makePreviewContainer() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        fallbackIconView.translatesAutoresizingMaskIntoConstraints = false
        fallbackIconView.imageScaling = .scaleProportionallyUpOrDown
        fallbackInitialLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackInitialLabel.alignment = .center
        fallbackInitialLabel.font = .systemFont(ofSize: 26, weight: .semibold)
        fallbackInitialLabel.textColor = .white

        container.addSubview(previewImageView)
        container.addSubview(fallbackIconView)
        container.addSubview(fallbackInitialLabel)

        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: container.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            fallbackIconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            fallbackIconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            fallbackIconView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.45),
            fallbackIconView.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: 0.45),
            fallbackInitialLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            fallbackInitialLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            fallbackInitialLabel.widthAnchor.constraint(equalTo: container.widthAnchor),
        ])

        return container
    }

    private func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        field.maximumNumberOfLines = 1
        return field
    }
}
