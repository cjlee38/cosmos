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

    var connectedDisplays: [WorkspaceSettingsDisplay] {
        displays
            .filter { $0.monitorSlot != nil }
            .sorted { ($0.monitorSlot ?? 0) < ($1.monitorSlot ?? 0) }
    }

    init(
        config: KkaciConfig,
        monitorSlots: [MonitorSlotSnapshot],
        displays: [DisplaySnapshot]
    ) {
        let slotByDisplayID = Dictionary(uniqueKeysWithValues: monitorSlots.map {
            ($0.display.id, $0.slot)
        })
        let workspaceItems = config.workspaces.names.map { workspace in
            WorkspaceSettingsItem(
                name: workspace,
                monitorSlot: config.workspaces.monitorSlot(for: workspace),
                switchShortcut: Self.shortcut(
                    command: "workspace",
                    workspace: workspace,
                    in: config.bindings
                ),
                moveShortcut: Self.shortcut(
                    command: "move-window-to-workspace",
                    workspace: workspace,
                    in: config.bindings
                )
            )
        }
        let namesByMonitorSlot = Dictionary(grouping: workspaceItems, by: \.monitorSlot)
            .mapValues { $0.map(\.name) }

        self.displays = displays.map { display in
            let monitorSlot = slotByDisplayID[display.id]
            let mirroredSourceMonitorSlot: MonitorSlot?
            if case let .mirrored(source) = display.role {
                mirroredSourceMonitorSlot = slotByDisplayID[source]
            } else {
                mirroredSourceMonitorSlot = nil
            }
            return WorkspaceSettingsDisplay(
                name: display.name,
                frame: display.frame,
                role: display.role,
                monitorSlot: monitorSlot,
                mirroredSourceMonitorSlot: mirroredSourceMonitorSlot,
                workspaceNames: monitorSlot.flatMap { namesByMonitorSlot[$0] } ?? []
            )
        }

        let connectedSlots = Set(monitorSlots.map(\.slot))
        disconnectedMonitorSlots = Set(workspaceItems.map(\.monitorSlot))
            .subtracting(connectedSlots)
            .sorted()
        navigation = WorkspaceNavigationShortcuts(
            next: Self.shortcut(command: "next-workspace", workspace: nil, in: config.bindings),
            previous: Self.shortcut(command: "previous-workspace", workspace: nil, in: config.bindings)
        )
        workspaces = workspaceItems
    }

    private static func shortcut(
        command: String,
        workspace: String?,
        in bindings: [HotKeyBinding]
    ) -> String? {
        bindings.first {
            $0.command == command && $0.workspace == workspace
        }?.key
    }
}

struct WorkspaceSettingsDisplay: Equatable {
    let name: String
    let frame: CGRect
    let role: DisplayRole
    let monitorSlot: MonitorSlot?
    let mirroredSourceMonitorSlot: MonitorSlot?
    let workspaceNames: [String]
}

struct WorkspaceNavigationShortcuts: Equatable {
    let next: String?
    let previous: String?
}

struct WorkspaceSettingsItem: Equatable {
    let name: String
    let monitorSlot: MonitorSlot
    let switchShortcut: String?
    let moveShortcut: String?
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
