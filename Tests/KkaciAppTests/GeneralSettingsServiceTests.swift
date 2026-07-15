@testable import KkaciApp
import XCTest

final class GeneralSettingsServiceTests: XCTestCase {
    func testSnapshotReadsLaunchAndPermissionState() {
        let service = GeneralSettingsService(
            launchAtLoginStatusProvider: { .requiresApproval },
            setLaunchAtLoginHandler: { _ in },
            permissionStatusProvider: { $0 != .inputMonitoring },
            openPermissionSettingsHandler: { _ in },
            openLoginItemsSettingsHandler: {}
        )

        let snapshot = service.snapshot()

        XCTAssertEqual(snapshot.launchAtLoginStatus, .requiresApproval)
        XCTAssertEqual(snapshot.permissions.map(\.permission), SettingsPermission.allCases)
        XCTAssertEqual(snapshot.permissions.map(\.isGranted), [true, false, true])
    }

    func testLaunchAtLoginChangeIsForwarded() throws {
        var requestedValues: [Bool] = []
        let service = GeneralSettingsService(
            launchAtLoginStatusProvider: { .disabled },
            setLaunchAtLoginHandler: { requestedValues.append($0) },
            permissionStatusProvider: { _ in false },
            openPermissionSettingsHandler: { _ in },
            openLoginItemsSettingsHandler: {}
        )

        try service.setLaunchAtLoginEnabled(true)
        try service.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(requestedValues, [true, false])
    }

    func testSystemSettingsActionsAreForwarded() {
        var openedPermission: SettingsPermission?
        var didOpenLoginItems = false
        let service = GeneralSettingsService(
            launchAtLoginStatusProvider: { .disabled },
            setLaunchAtLoginHandler: { _ in },
            permissionStatusProvider: { _ in false },
            openPermissionSettingsHandler: { openedPermission = $0 },
            openLoginItemsSettingsHandler: { didOpenLoginItems = true }
        )

        service.openSystemSettings(for: .screenRecording)
        service.openLoginItemsSettings()

        XCTAssertEqual(openedPermission, .screenRecording)
        XCTAssertTrue(didOpenLoginItems)
    }
}
