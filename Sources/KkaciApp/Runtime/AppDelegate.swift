import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let runtime: AppRuntime

    init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    func applicationDidFinishLaunching(_: Notification) {
        runtime.start()
    }

    func applicationWillTerminate(_: Notification) {
        runtime.shutdown()
    }
}
