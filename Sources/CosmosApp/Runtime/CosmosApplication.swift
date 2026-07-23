import AppKit

enum CosmosApplication {
    static func run() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            app.run()
            return
        }

        let appDelegate = AppDelegate(
            runtime: AppCompositionRoot().build(),
            applicationIconController: RuntimeApplicationIconController(application: app)
        )
        app.delegate = appDelegate
        app.mainMenu = makeMainMenu(for: app)
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private func makeMainMenu(for app: NSApplication) -> NSMenu {
    let mainMenu = NSMenu()
    let applicationItem = NSMenuItem(title: "Cosmos", action: nil, keyEquivalent: "")
    let applicationMenu = NSMenu(title: "Cosmos")

    let aboutItem = NSMenuItem(
        title: "About Cosmos",
        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
        keyEquivalent: ""
    )
    aboutItem.target = app
    applicationMenu.addItem(aboutItem)
    applicationMenu.addItem(.separator())

    let hideItem = NSMenuItem(
        title: "Hide Cosmos",
        action: #selector(NSApplication.hide(_:)),
        keyEquivalent: "h"
    )
    hideItem.target = app
    applicationMenu.addItem(hideItem)

    let quitItem = NSMenuItem(
        title: "Quit Cosmos",
        action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"
    )
    quitItem.target = app
    applicationMenu.addItem(quitItem)

    applicationItem.submenu = applicationMenu
    mainMenu.addItem(applicationItem)
    return mainMenu
}
