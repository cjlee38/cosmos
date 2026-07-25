@testable import CosmosApp
import XCTest

final class GeneralSettingsServiceTests: XCTestCase {
    func testSnapshotReadsLaunchAndPermissionState() {
        let service = GeneralSettingsService(
            launchAtLoginStatusProvider: { .requiresApproval },
            setLaunchAtLoginHandler: { _ in },
            permissionStatusProvider: { $0 == .accessibility },
            openPermissionSettingsHandler: { _ in },
            openLoginItemsSettingsHandler: {}
        )

        let snapshot = service.snapshot()

        XCTAssertEqual(snapshot.launchAtLoginStatus, .requiresApproval)
        XCTAssertEqual(snapshot.permissions.map(\.permission), SettingsPermission.allCases)
        XCTAssertEqual(snapshot.permissions.map(\.isGranted), [true, false])
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

    func testPermissionRequestIsForwarded() {
        var requestedPermission: SettingsPermission?
        let service = GeneralSettingsService(
            launchAtLoginStatusProvider: { .disabled },
            setLaunchAtLoginHandler: { _ in },
            permissionStatusProvider: { _ in false },
            requestPermissionHandler: { requestedPermission = $0 },
            openPermissionSettingsHandler: { _ in },
            openLoginItemsSettingsHandler: {}
        )

        service.requestPermission(.accessibility)

        XCTAssertEqual(requestedPermission, .accessibility)
    }

    func testOnboardingRequiresCurrentVersionUntilCompleted() throws {
        let suiteName = "OnboardingStateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingStateStore(defaults: defaults)

        XCTAssertTrue(store.requiresOnboarding)

        store.markCompleted()

        XCTAssertFalse(store.requiresOnboarding)
    }

    func testOnboardingRunsAgainWhenStoredVersionIsOlder() throws {
        let suiteName = "OnboardingStateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(OnboardingStateStore.currentVersion - 1, forKey: "onboarding.completedVersion")

        XCTAssertTrue(OnboardingStateStore(defaults: defaults).requiresOnboarding)
    }
}
