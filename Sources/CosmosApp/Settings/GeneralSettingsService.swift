import AppKit
import CoreGraphics
import CosmosCore
import ServiceManagement

final class GeneralSettingsService {
    private let launchAtLoginStatusProvider: () -> LaunchAtLoginStatus
    private let setLaunchAtLoginHandler: (Bool) throws -> Void
    private let permissionStatusProvider: (SettingsPermission) -> Bool
    private let requestPermissionHandler: (SettingsPermission) -> Void
    private let openPermissionSettingsHandler: (SettingsPermission) -> Void
    private let openLoginItemsSettingsHandler: () -> Void

    convenience init(axClient: AXClient) {
        let service = SMAppService.mainApp
        self.init(
            launchAtLoginStatusProvider: {
                Self.launchAtLoginStatus(for: service)
            },
            setLaunchAtLoginHandler: { enabled in
                try Self.setLaunchAtLogin(enabled, service: service)
            },
            permissionStatusProvider: { permission in
                Self.isPermissionGranted(permission, axClient: axClient)
            },
            requestPermissionHandler: { permission in
                Self.requestPermission(permission, axClient: axClient)
            },
            openPermissionSettingsHandler: { permission in
                guard let url = Self.systemSettingsURL(for: permission) else {
                    return
                }
                NSWorkspace.shared.open(url)
            },
            openLoginItemsSettingsHandler: {
                SMAppService.openSystemSettingsLoginItems()
            }
        )
    }

    init(
        launchAtLoginStatusProvider: @escaping () -> LaunchAtLoginStatus,
        setLaunchAtLoginHandler: @escaping (Bool) throws -> Void,
        permissionStatusProvider: @escaping (SettingsPermission) -> Bool,
        requestPermissionHandler: @escaping (SettingsPermission) -> Void = { _ in },
        openPermissionSettingsHandler: @escaping (SettingsPermission) -> Void,
        openLoginItemsSettingsHandler: @escaping () -> Void
    ) {
        self.launchAtLoginStatusProvider = launchAtLoginStatusProvider
        self.setLaunchAtLoginHandler = setLaunchAtLoginHandler
        self.permissionStatusProvider = permissionStatusProvider
        self.requestPermissionHandler = requestPermissionHandler
        self.openPermissionSettingsHandler = openPermissionSettingsHandler
        self.openLoginItemsSettingsHandler = openLoginItemsSettingsHandler
    }

    func snapshot() -> GeneralSettingsSnapshot {
        GeneralSettingsSnapshot(
            launchAtLoginStatus: launchAtLoginStatusProvider(),
            permissions: SettingsPermission.allCases.map {
                SettingsPermissionStatus(permission: $0, isGranted: permissionStatusProvider($0))
            }
        )
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
        try setLaunchAtLoginHandler(enabled)
    }

    func openSystemSettings(for permission: SettingsPermission) {
        openPermissionSettingsHandler(permission)
    }

    func requestPermission(_ permission: SettingsPermission) {
        requestPermissionHandler(permission)
    }

    func openLoginItemsSettings() {
        openLoginItemsSettingsHandler()
    }

    private static func systemSettingsURL(for permission: SettingsPermission) -> URL? {
        let anchor = switch permission {
        case .accessibility:
            "Privacy_Accessibility"
        case .screenRecording:
            "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    private static func launchAtLoginStatus(for service: SMAppService) -> LaunchAtLoginStatus {
        switch service.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .disabled
        @unknown default:
            .disabled
        }
    }

    private static func setLaunchAtLogin(_ enabled: Bool, service: SMAppService) throws {
        if enabled {
            guard service.status != .enabled else {
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered, service.status != .notFound else {
                return
            }
            try service.unregister()
        }
    }

    private static func isPermissionGranted(
        _ permission: SettingsPermission,
        axClient: AXClient
    ) -> Bool {
        switch permission {
        case .accessibility:
            axClient.ensureAccessibilityPermission(prompt: false)
        case .screenRecording:
            CGPreflightScreenCaptureAccess()
        }
    }

    private static func requestPermission(
        _ permission: SettingsPermission,
        axClient: AXClient
    ) {
        switch permission {
        case .accessibility:
            _ = axClient.ensureAccessibilityPermission(prompt: true)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        }
    }
}
