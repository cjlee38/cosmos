import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime: AppRuntime
    private let applicationIconController: RuntimeApplicationIconController

    init(
        runtime: AppRuntime,
        applicationIconController: RuntimeApplicationIconController
    ) {
        self.runtime = runtime
        self.applicationIconController = applicationIconController
    }

    func applicationDidFinishLaunching(_: Notification) {
        applicationIconController.start()
        runtime.start()
    }

    func applicationWillTerminate(_: Notification) {
        runtime.shutdown()
    }
}
