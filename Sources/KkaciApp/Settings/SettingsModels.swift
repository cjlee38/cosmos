import Foundation
import KkaciCore

enum SettingsSection: CaseIterable, Hashable {
    case general
    case switcher
    case workspaces

    var title: String {
        switch self {
        case .general:
            "General"
        case .switcher:
            "Switcher"
        case .workspaces:
            "Workspaces"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape"
        case .switcher:
            "rectangle.on.rectangle"
        case .workspaces:
            "rectangle.3.group"
        }
    }
}

enum SettingsPermission: CaseIterable, Hashable {
    case accessibility
    case screenRecording

    var title: String {
        switch self {
        case .accessibility:
            "Accessibility"
        case .screenRecording:
            "Screen Recording"
        }
    }
}

struct SettingsPermissionStatus {
    let permission: SettingsPermission
    let isGranted: Bool
}

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
}

struct GeneralSettingsSnapshot {
    let launchAtLoginStatus: LaunchAtLoginStatus
    let permissions: [SettingsPermissionStatus]
}

enum MenuBarIconStyle: String, CaseIterable {
    case angleBrackets
    case squareBrackets

    var preview: String {
        switch self {
        case .angleBrackets:
            "<•X | Y>"
        case .squareBrackets:
            "[•X | Y]"
        }
    }
}

enum SwitcherSizeRange {
    static let window = 1.0 ... 2.5
    static let workspace = 0.0 ... 1.0
    static let defaultWindow = 1.75
    static let defaultWorkspace = 0.5
}

struct AppSettingsSnapshot: Equatable {
    let menuBarIconStyle: MenuBarIconStyle
    let windowSwitcherSize: Double
    let workspaceSwitcherSize: Double
}

struct WorkspaceSettingsSnapshot: Equatable {
    let displays: [WorkspaceSettingsDisplay]
    let disconnectedMonitorSlots: [MonitorSlot]
    let workspaceSwitcher: SwitcherSettingsShortcuts
    let windowSwitcher: SwitcherSettingsShortcuts
    let workspaces: [WorkspaceSettingsItem]
    let isEditable: Bool
    let shortcutValidationMessages: [ShortcutTarget: String]

    var availableWorkspaceIDs: [WorkspaceID] {
        let configuredIDs = Set(workspaces.map(\.id))
        return WorkspaceID.allCases.filter { !configuredIDs.contains($0) }
    }

    init(
        config: KkaciConfig,
        monitorSlots: [MonitorSlotSnapshot],
        workspaceWindowCounts: [WorkspaceID: Int] = [:],
        isEditable: Bool = true,
        shortcutValidationMessages: [ShortcutTarget: String] = [:]
    ) {
        let workspaceItems = config.workspaces.map { workspace in
            WorkspaceSettingsItem(
                id: workspace.id,
                monitorSlot: workspace.display,
                switchShortcut: workspace.shortcuts.switchWorkspace,
                moveShortcut: workspace.shortcuts.moveWindow,
                windowCount: workspaceWindowCounts[workspace.id] ?? 0
            )
        }
        let idsByMonitorSlot = Dictionary(grouping: workspaceItems, by: \.monitorSlot)
            .mapValues { $0.map(\.id) }
        let displayFrames = monitorSlots.map(\.display.frame)
        displays = monitorSlots.map { monitorSlot in
            WorkspaceSettingsDisplay(
                id: monitorSlot.display.id,
                name: monitorSlot.display.name,
                frame: monitorSlot.display.frame,
                role: monitorSlot.display.role,
                monitorSlot: monitorSlot.slot,
                workspaceIDs: idsByMonitorSlot[monitorSlot.slot] ?? [],
                hasUnobstructedParkingCorner: WindowParkingPointProvider.assessment(
                    for: monitorSlot.display.frame,
                    among: displayFrames
                ).hasUnobstructedCorner
            )
        }

        let connectedSlots = Set(monitorSlots.map(\.slot))
        disconnectedMonitorSlots = Set(workspaceItems.map(\.monitorSlot))
            .subtracting(connectedSlots)
            .sorted()
        workspaceSwitcher = SwitcherSettingsShortcuts(
            next: config.shortcuts.workspaceSwitcher.next,
            previous: config.shortcuts.workspaceSwitcher.previous
        )
        windowSwitcher = SwitcherSettingsShortcuts(
            next: config.shortcuts.windowSwitcher.next,
            previous: config.shortcuts.windowSwitcher.previous
        )
        workspaces = workspaceItems
        self.isEditable = isEditable
        self.shortcutValidationMessages = shortcutValidationMessages
    }

    func shortcutValidationMessage(for target: ShortcutTarget) -> String? {
        shortcutValidationMessages[target]
    }
}

struct WorkspaceSettingsDisplay: Equatable {
    let id: DisplayID
    let name: String
    let frame: CGRect
    let role: DisplayRole
    let monitorSlot: MonitorSlot
    let workspaceIDs: [WorkspaceID]
    let hasUnobstructedParkingCorner: Bool

    init(
        id: DisplayID,
        name: String,
        frame: CGRect,
        role: DisplayRole,
        monitorSlot: MonitorSlot,
        workspaceIDs: [WorkspaceID],
        hasUnobstructedParkingCorner: Bool = true
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.role = role
        self.monitorSlot = monitorSlot
        self.workspaceIDs = workspaceIDs
        self.hasUnobstructedParkingCorner = hasUnobstructedParkingCorner
    }
}

struct WorkspaceDisplayOption: Equatable {
    let displayID: DisplayID
    let monitorSlot: MonitorSlot
    let name: String

    init(displayID: DisplayID, monitorSlot: MonitorSlot, name: String) {
        self.displayID = displayID
        self.monitorSlot = monitorSlot
        self.name = name
    }

    init(display: WorkspaceSettingsDisplay) {
        displayID = display.id
        monitorSlot = display.monitorSlot
        name = display.name
    }

    var title: String {
        "\(monitorSlot) · \(name)"
    }
}

struct SwitcherSettingsShortcuts: Equatable {
    let next: String?
    let previous: String?
}

struct WorkspaceSettingsItem: Equatable {
    let id: WorkspaceID
    let monitorSlot: MonitorSlot
    let switchShortcut: String?
    let moveShortcut: String?
    let windowCount: Int
}

enum ShortcutDisplayFormatter {
    static func format(_ shortcut: String?) -> String {
        guard let shortcut else {
            return "-"
        }
        guard let parsed = try? Shortcut(parsing: shortcut) else {
            return shortcut
        }
        return (parsed.modifiers.map(formatModifier) + [formatKey(parsed.key)])
            .joined(separator: " ")
    }

    private static func formatModifier(_ modifier: ShortcutModifier) -> String {
        switch modifier {
        case .command:
            "⌘"
        case .control:
            "⌃"
        case .option:
            "⌥"
        case .shift:
            "⇧"
        }
    }

    private static func formatKey(_ key: String) -> String {
        switch key {
        case "tab":
            "Tab"
        default:
            key.uppercased()
        }
    }
}
