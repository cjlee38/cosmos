import Foundation
import CosmosCore

enum SettingsSection: CaseIterable, Hashable {
    case general
    case switcher
    case spaces
    case window

    var title: String {
        switch self {
        case .general:
            "General"
        case .switcher:
            "Switcher"
        case .window:
            "Window"
        case .spaces:
            "Spaces"
        }
    }

    var symbolName: String {
        switch self {
        case .general:
            "gearshape"
        case .switcher:
            "rectangle.on.rectangle"
        case .window:
            "macwindow"
        case .spaces:
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
    static let space = 0.0 ... 1.0
    static let defaultWindow = 1.75
    static let defaultSpace = 0.5
}

struct AppSettingsSnapshot: Equatable {
    let menuBarIconStyle: MenuBarIconStyle
    let windowSwitcherSize: Double
    let spaceSwitcherSize: Double
}

struct SpaceSettingsSnapshot: Equatable {
    let displays: [SpaceSettingsDisplay]
    let disconnectedMonitorSlots: [MonitorSlot]
    let spaceSwitcher: String?
    let windowSwitcher: String?
    let centerWindow: String?
    let spaces: [SpaceSettingsItem]
    let isEditable: Bool
    let shortcutValidationMessages: [ShortcutTarget: String]

    init(
        config: CosmosConfig,
        monitorSlots: [MonitorSlotSnapshot],
        spaceWindowCounts: [SpaceID: Int] = [:],
        isEditable: Bool = true,
        shortcutValidationMessages: [ShortcutTarget: String] = [:]
    ) {
        let spaceItems = config.spaces.map { space in
            SpaceSettingsItem(
                id: space.id,
                monitorSlot: space.display,
                switchShortcut: space.shortcuts.switchSpace,
                moveShortcut: space.shortcuts.moveWindow,
                windowCount: spaceWindowCounts[space.id] ?? 0
            )
        }
        let idsByMonitorSlot = Dictionary(grouping: spaceItems, by: \.monitorSlot)
            .mapValues { $0.map(\.id) }
        let displayFrames = monitorSlots.map(\.display.frame)
        displays = monitorSlots.map { monitorSlot in
            SpaceSettingsDisplay(
                id: monitorSlot.display.id,
                name: monitorSlot.display.name,
                frame: monitorSlot.display.frame,
                role: monitorSlot.display.role,
                monitorSlot: monitorSlot.slot,
                spaceIDs: idsByMonitorSlot[monitorSlot.slot] ?? [],
                hasUnobstructedParkingCorner: WindowParkingPointProvider.assessment(
                    for: monitorSlot.display.frame,
                    among: displayFrames
                ).hasUnobstructedCorner
            )
        }

        let connectedSlots = Set(monitorSlots.map(\.slot))
        disconnectedMonitorSlots = Set(spaceItems.map(\.monitorSlot))
            .subtracting(connectedSlots)
            .sorted()
        spaceSwitcher = config.switcher.shortcuts.space
        windowSwitcher = config.switcher.shortcuts.window
        centerWindow = config.window.shortcuts.center
        spaces = spaceItems
        self.isEditable = isEditable
        self.shortcutValidationMessages = shortcutValidationMessages
    }

    func shortcutValidationMessage(for target: ShortcutTarget) -> String? {
        shortcutValidationMessages[target]
    }
}

struct SpaceSettingsDisplay: Equatable {
    let id: DisplayID
    let name: String
    let frame: CGRect
    let role: DisplayRole
    let monitorSlot: MonitorSlot
    let spaceIDs: [SpaceID]
    let hasUnobstructedParkingCorner: Bool

    init(
        id: DisplayID,
        name: String,
        frame: CGRect,
        role: DisplayRole,
        monitorSlot: MonitorSlot,
        spaceIDs: [SpaceID],
        hasUnobstructedParkingCorner: Bool = true
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.role = role
        self.monitorSlot = monitorSlot
        self.spaceIDs = spaceIDs
        self.hasUnobstructedParkingCorner = hasUnobstructedParkingCorner
    }
}

struct SpaceDisplayOption: Equatable {
    let monitorSlot: MonitorSlot
    let name: String

    init(display: SpaceSettingsDisplay) {
        monitorSlot = display.monitorSlot
        name = display.name
    }

    var title: String {
        "\(monitorSlot) · \(name)"
    }
}

struct SpaceSettingsItem: Equatable {
    let id: SpaceID
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
