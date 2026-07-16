import Foundation

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
            "<*X | Y>"
        case .squareBrackets:
            "[*X | Y]"
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
