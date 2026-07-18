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
    let workspaceSwitcher: SwitcherSettingsShortcuts
    let windowSwitcher: SwitcherSettingsShortcuts
    let workspaces: [WorkspaceSettingsItem]
    let isEditable: Bool
    let shortcutValidationMessages: [ShortcutTarget: String]

    var availableWorkspaceIDs: [WorkspaceID] {
        let configuredIDs = Set(workspaces.map(\.id))
        return WorkspaceID.allCases.filter { !configuredIDs.contains($0) }
    }

    var workspaceDisplayOptions: [WorkspaceDisplayOption] {
        displays
            .map(WorkspaceDisplayOption.init)
            .sorted { $0.monitorSlot < $1.monitorSlot }
    }

    init(
        config: KkaciConfig,
        monitorSlots: [MonitorSlotSnapshot],
        isEditable: Bool = true,
        shortcutValidationMessages: [ShortcutTarget: String] = [:]
    ) {
        let workspaceItems = config.workspaces.map { workspace in
            WorkspaceSettingsItem(
                id: workspace.id,
                monitorSlot: workspace.display,
                switchShortcut: workspace.shortcuts.switchWorkspace,
                moveShortcut: workspace.shortcuts.moveWindow
            )
        }
        let idsByMonitorSlot = Dictionary(grouping: workspaceItems, by: \.monitorSlot)
            .mapValues { $0.map(\.id) }
        displays = monitorSlots.map { monitorSlot in
            WorkspaceSettingsDisplay(
                id: monitorSlot.display.id,
                name: monitorSlot.display.name,
                frame: monitorSlot.display.frame,
                role: monitorSlot.display.role,
                monitorSlot: monitorSlot.slot,
                workspaceIDs: idsByMonitorSlot[monitorSlot.slot] ?? []
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
}

enum ShortcutDisplayFormatter {
    static func format(_ shortcut: String?) -> String {
        guard let shortcut else {
            return "Not set"
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
