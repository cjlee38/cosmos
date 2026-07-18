import AppKit

let app = NSApplication.shared
let appDelegate = AppDelegate(runtime: AppCompositionRoot().build())
app.delegate = appDelegate
app.mainMenu = makeMainMenu(for: app)
app.setActivationPolicy(.accessory)
app.run()

private func makeMainMenu(for app: NSApplication) -> NSMenu {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem(title: "Kkaci", action: nil, keyEquivalent: "")
    let applicationMenu = NSMenu(title: "Kkaci")

    let aboutItem = NSMenuItem(
        title: "About Kkaci",
        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        keyEquivalent: ""
    )
    aboutItem.target = app
    applicationMenu.addItem(aboutItem)
    applicationMenu.addItem(.separator())

    let hideItem = NSMenuItem(
        title: "Hide Kkaci",
        action: #selector(NSApplication.hide(_:)),
        keyEquivalent: "h"
    )
    hideItem.target = app
    applicationMenu.addItem(hideItem)

    let quitItem = NSMenuItem(
        title: "Quit Kkaci",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    quitItem.target = app
    applicationMenu.addItem(quitItem)

    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)
    return mainMenu
}
