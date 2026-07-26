import AppKit
import CosmosCore

final class SpaceDisplayCardView: NSView {
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

        let heading = makeHeading(for: item)
        configureParkingWarning(message: parkingMessage, monitorSlot: item.monitorSlot)
        configureSpaceFlow()

        addSubview(heading)
        addSubview(parkingWarning)
        addSubview(spaceFlow)
        constrain(heading: heading)
    }

    private func makeHeading(for item: SpaceSettingsDisplay) -> NSView {
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
        return heading
    }

    private func configureParkingWarning(message: String, monitorSlot: Int) {
        parkingWarning.image = NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: "Unsafe display arrangement"
        )
        parkingWarning.isBordered = false
        parkingWarning.contentTintColor = .systemRed
        parkingWarning.toolTip = isParkingObstructed ? message : nil
        parkingWarning.isHidden = !isParkingObstructed
        parkingWarning.target = self
        parkingWarning.action = #selector(showParkingWarning)
        parkingWarning.translatesAutoresizingMaskIntoConstraints = false
        parkingWarning.setAccessibilityIdentifier(
            "cosmos.settings.display-parking-warning.\(monitorSlot)"
        )
    }

    private func configureSpaceFlow() {
        spaceFlow.translatesAutoresizingMaskIntoConstraints = false
        spaceFlow.onSpaceSelected = { [weak self] spaceID in
            self?.onSpaceSelected?(spaceID)
        }
        spaceFlow.onOverflowSelected = { [weak self] spaceIDs, sourceView in
            self?.showOverflow(spaceIDs, relativeTo: sourceView)
        }
    }

    private func constrain(heading: NSView) {
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
