import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtimeHost: ApplicationRuntimeHost

    init(runtimeHost: ApplicationRuntimeHost) {
        self.runtimeHost = runtimeHost
    }

    func applicationDidFinishLaunching(_: Notification) {
        runtimeHost.start()
    }

    func applicationWillTerminate(_: Notification) {
        runtimeHost.shutdown()
    }
}
