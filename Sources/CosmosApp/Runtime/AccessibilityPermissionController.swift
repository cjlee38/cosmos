import CosmosCore

final class AccessibilityPermissionController {
    private let axClient: AXClient

    init(axClient: AXClient) {
        self.axClient = axClient
    }

    func checkAtLaunch() -> Bool {
        axClient.ensureAccessibilityPermission(prompt: true)
    }
}
