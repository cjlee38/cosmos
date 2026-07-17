import AppKit
import KkaciCore

final class WorkspaceMonitorPopUpButton: NSPopUpButton {
    let workspaceID: WorkspaceID
    let currentMonitorSlot: MonitorSlot

    init(
        workspaceID: WorkspaceID,
        currentMonitorSlot: MonitorSlot,
        connectedDisplays: [WorkspaceSettingsDisplay]
    ) {
        self.workspaceID = workspaceID
        self.currentMonitorSlot = currentMonitorSlot
        super.init(frame: .zero, pullsDown: false)

        setAccessibilityIdentifier("kkaci.settings.workspace.\(workspaceID.rawValue).monitor")
        controlSize = .small
        font = .systemFont(ofSize: 12, weight: .medium)
        let labelsByMonitorSlot = Dictionary(uniqueKeysWithValues: connectedDisplays.compactMap { display in
            display.monitorSlot.map { monitorSlot in
                (monitorSlot, display.name)
            }
        })
        let availableSlots = Set(labelsByMonitorSlot.keys)
        let options = availableSlots.union([currentMonitorSlot]).sorted()
        for monitorSlot in options {
            let isConnected = availableSlots.contains(monitorSlot)
            let title = labelsByMonitorSlot[monitorSlot] ?? "Monitor \(monitorSlot)"
            addItem(withTitle: title)
            let item = itemArray[itemArray.count - 1]
            item.representedObject = monitorSlot
            item.isEnabled = isConnected
            if !isConnected {
                item.title += " · Disconnected"
            }
            if monitorSlot == currentMonitorSlot {
                select(item)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceAddButton: NSButton {
    let availableWorkspaceIDs: [WorkspaceID]

    init(availableWorkspaceIDs: [WorkspaceID]) {
        self.availableWorkspaceIDs = availableWorkspaceIDs
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceRemoveButton: NSButton {
    let workspaceID: WorkspaceID

    init(workspaceID: WorkspaceID) {
        self.workspaceID = workspaceID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceIDMenuItem: NSMenuItem {
    let workspaceID: WorkspaceID

    init(workspaceID: WorkspaceID) {
        self.workspaceID = workspaceID
        super.init(title: workspaceID.rawValue, action: nil, keyEquivalent: "")
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class WorkspaceAddMenu: NSMenu {
    init(workspaceIDs: [WorkspaceID], target: AnyObject, action: Selector) {
        super.init(title: "Add Workspace")
        for workspaceID in workspaceIDs {
            let item = WorkspaceIDMenuItem(workspaceID: workspaceID)
            item.target = target
            item.action = action
            addItem(item)
        }
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class ShortcutBadgeView: NSView {
    init(title: String, isConfigured: Bool) {
        super.init(frame: .zero)
        wantsLayer = true

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = isConfigured ? .labelColor : .tertiaryLabelColor
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
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
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        layer?.cornerRadius = 6
    }
}
