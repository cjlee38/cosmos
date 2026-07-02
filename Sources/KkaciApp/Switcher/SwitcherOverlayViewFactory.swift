import AppKit

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
    ) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = compact ? 8 : 12
        let tileWidth: CGFloat = compact ? 112 : 176
        let height: CGFloat = compact ? 122 : 318

        if items.isEmpty {
            let empty = label("No windows", font: .systemFont(ofSize: 15), color: .secondaryLabelColor)
            empty.frame = NSRect(x: 0, y: 0, width: 180, height: 80)
            stack.addArrangedSubview(empty)
        } else {
            for (index, item) in items.enumerated() {
                stack.addArrangedSubview(makeWindowTile(
                    item,
                    isSelected: index == selectedIndex,
                    compact: compact
                ))
            }
        }
        let width = items.isEmpty
            ? CGFloat(180)
            : CGFloat(items.count) * tileWidth + CGFloat(max(items.count - 1, 0)) * stack.spacing
        stack.frame = NSRect(x: 0, y: 0, width: width, height: height)

        return horizontalScrollView(documentView: stack)
    }

    func makeWorkspaceList(groups: [WorkspaceSwitcherGroup], selectedIndex: Int) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        for (index, group) in groups.enumerated() {
            stack.addArrangedSubview(makeWorkspaceGroup(group, isSelected: index == selectedIndex))
        }
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: CGFloat(max(groups.count, 1)) * 260 + CGFloat(max(groups.count - 1, 0)) * stack.spacing,
            height: 250
        )

        return horizontalScrollView(documentView: stack)
    }

    private func horizontalScrollView(documentView: NSView) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = documentView
        return scrollView
    }

    private func makeWorkspaceGroup(_ group: WorkspaceSwitcherGroup, isSelected: Bool) -> NSView {
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

        return container
    }

    private func makeWindowTile(
        _ item: WindowSwitcherItem,
        isSelected: Bool,
        compact: Bool
    ) -> NSView {
        let preview: NSView = item.preview.map { makePreviewImage($0) } ?? makeFallbackPreview(item)
        preview.translatesAutoresizingMaskIntoConstraints = false

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

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = isSelected ? 2 : 1
        container.layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.white.withAlphaComponent(0.14).cgColor
        container.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.2).cgColor
            : NSColor.black.withAlphaComponent(0.2).cgColor

        container.addSubview(stack)

        let tileWidth: CGFloat = compact ? 112 : 176
        let previewHeight: CGFloat = compact ? 68 : 108
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: tileWidth),
            container.heightAnchor.constraint(equalToConstant: compact ? 116 : 192),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: compact ? 8 : 10),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: compact ? 8 : 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: compact ? -8 : -10),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: previewHeight),
            appLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        return container
    }

    private func makePreviewImage(_ image: NSImage) -> NSImageView {
        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        return imageView
    }

    private func makeFallbackPreview(_ item: WindowSwitcherItem) -> NSView {
        let iconView = NSImageView(image: item.icon ?? NSImage())
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let initial = item.appName.first.map(String.init) ?? "?"
        let initialLabel = label(initial, font: .systemFont(ofSize: 26, weight: .semibold), color: .white)
        initialLabel.alignment = .center
        initialLabel.translatesAutoresizingMaskIntoConstraints = false
        initialLabel.isHidden = item.icon != nil

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        container.addSubview(iconView)
        container.addSubview(initialLabel)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            iconView.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.45),
            iconView.heightAnchor.constraint(lessThanOrEqualTo: container.heightAnchor, multiplier: 0.45),
            initialLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            initialLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            initialLabel.widthAnchor.constraint(equalTo: container.widthAnchor),
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
