import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate(runtime: AppCompositionRoot().build())
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
