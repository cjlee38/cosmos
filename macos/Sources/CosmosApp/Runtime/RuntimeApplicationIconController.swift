import AppKit

final class RuntimeApplicationIconController {
    private let application: NSApplication
    private let bundle: Bundle
    private var appearanceObservation: NSKeyValueObservation?
    private var activationObserver: NSObjectProtocol?

    init(application: NSApplication = .shared, bundle: Bundle = .main) {
        self.application = application
        self.bundle = bundle
    }

    func start() {
        updateIcon()
        appearanceObservation = application.observe(\.effectiveAppearance) { [weak self] _, _ in
            self?.updateIcon()
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: application,
            queue: .main
        ) { [weak self] _ in
            self?.updateIcon()
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    private func updateIcon() {
        let isDark = application.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let resourceName = isDark ? "CosmosRuntimeIconDark" : "CosmosRuntimeIconLight"
        guard let url = bundle.url(forResource: resourceName, withExtension: "png"),
              let icon = NSImage(contentsOf: url)
        else {
            return
        }

        application.applicationIconImage = icon
    }
}
