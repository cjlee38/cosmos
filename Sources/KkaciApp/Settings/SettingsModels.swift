import Foundation
import KkaciCore

enum SettingsSection: CaseIterable, Hashable {
    case general
    case appearance
    case workspaces

    var title: String {
        switch self {
        case .general:
            "General"
        case .appearance:
            "Appearance"
        case .workspaces:
            "Workspaces"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape"
        case .appearance:
            "paintbrush"
        case .workspaces:
            "rectangle.3.group"
        }
    }
}

enum SettingsPermission: CaseIterable, Hashable {
    case accessibility
    case inputMonitoring
    case screenRecording

    var title: String {
        switch self {
        case .accessibility:
            "Accessibility"
        case .inputMonitoring:
            "Input Monitoring"
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
    let navigation: WorkspaceNavigationShortcuts
    let workspaces: [WorkspaceSettingsItem]

    var availableWorkspaceIDs: [WorkspaceID] {
        let configuredIDs = Set(workspaces.map(\.id))
        return WorkspaceID.allCases.filter { !configuredIDs.contains($0) }
    }

    var workspaceDisplayOptions: [WorkspaceDisplayOption] {
        displays
            .map(WorkspaceDisplayOption.init)
            .sorted { lhs, rhs in
                (lhs.monitorSlot ?? .max) < (rhs.monitorSlot ?? .max)
            }
    }

    init(
        config: KkaciConfig,
        monitorSlots: [MonitorSlotSnapshot],
        displays: [DisplaySnapshot]
    ) {
        let slotByDisplayID = Dictionary(uniqueKeysWithValues: monitorSlots.map {
            ($0.display.id, $0.slot)
        })
        let workspaceItems = config.workspaces.map { workspace in
            WorkspaceSettingsItem(
                id: workspace.id,
                name: workspace.name,
                monitorSlot: workspace.display,
                switchShortcut: workspace.shortcuts.switchWorkspace,
                moveShortcut: workspace.shortcuts.moveWindow
            )
        }
        let idsByMonitorSlot = Dictionary(grouping: workspaceItems, by: \.monitorSlot)
            .mapValues { $0.map(\.id) }
        let titlesByMonitorSlot = Dictionary(grouping: workspaceItems, by: \.monitorSlot)
            .mapValues { $0.map(\.displayTitle) }

        self.displays = displays.map { display in
            let monitorSlot = slotByDisplayID[display.id]
            return WorkspaceSettingsDisplay(
                id: display.id,
                name: display.name,
                frame: display.frame,
                role: display.role,
                monitorSlot: monitorSlot,
                workspaceIDs: monitorSlot.flatMap { idsByMonitorSlot[$0] } ?? [],
                workspaceTitles: monitorSlot.flatMap { titlesByMonitorSlot[$0] } ?? []
            )
        }

        let connectedSlots = Set(monitorSlots.map(\.slot))
        disconnectedMonitorSlots = Set(workspaceItems.map(\.monitorSlot))
            .subtracting(connectedSlots)
            .sorted()
        navigation = WorkspaceNavigationShortcuts(
            next: config.shortcuts.workspaceSwitcher.next,
            previous: config.shortcuts.workspaceSwitcher.previous
        )
        workspaces = workspaceItems
    }
}

struct WorkspaceSettingsDisplay: Equatable {
    let id: DisplayID
    let name: String
    let frame: CGRect
    let role: DisplayRole
    let monitorSlot: MonitorSlot?
    let workspaceIDs: [WorkspaceID]
    let workspaceTitles: [String]
}

struct WorkspaceDisplayOption: Equatable {
    let displayID: DisplayID
    let monitorSlot: MonitorSlot?
    let name: String

    init(displayID: DisplayID, monitorSlot: MonitorSlot?, name: String) {
        self.displayID = displayID
        self.monitorSlot = monitorSlot
        self.name = name
    }

    init(display: WorkspaceSettingsDisplay) {
        displayID = display.id
        monitorSlot = display.monitorSlot
        name = display.name
    }

    var isEnabled: Bool {
        monitorSlot != nil
    }

    var title: String {
        if let monitorSlot {
            return "\(monitorSlot) · \(name)"
        }
        return name
    }
}

struct WorkspaceNavigationShortcuts: Equatable {
    let next: String?
    let previous: String?
}

struct WorkspaceSettingsItem: Equatable {
    let id: WorkspaceID
    let name: String?
    let monitorSlot: MonitorSlot
    let switchShortcut: String?
    let moveShortcut: String?

    var displayTitle: String {
        name.map { "\($0) (\(id.rawValue))" } ?? id.rawValue
    }
}

enum ShortcutDisplayFormatter {
    static func format(_ shortcut: String?) -> String {
        guard let shortcut else {
            return "Not set"
        }

        return shortcut
            .split(separator: "+")
            .map(formatToken)
            .joined(separator: " ")
    }

    private static func formatToken(_ token: Substring) -> String {
        switch token.lowercased() {
        case "command", "cmd":
            "⌘"
        case "control", "ctrl":
            "⌃"
        case "option", "alt":
            "⌥"
        case "shift":
            "⇧"
        case "tab":
            "Tab"
        default:
            token.uppercased()
        }
    }
}
