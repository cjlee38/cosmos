import AppKit
import Darwin

protocol ApplicationRelaunching: AnyObject {
    func launchReplacement(
        waitingFor processID: pid_t,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

enum ApplicationRelaunchError: LocalizedError {
    case launchReturnedNoApplication
    case launchAlreadyInProgress
    case replacementTerminatedDuringLaunch

    var errorDescription: String? {
        switch self {
        case .launchReturnedNoApplication:
            "macOS did not return a running application for the replacement Cosmos instance."
        case .launchAlreadyInProgress:
            "A replacement Cosmos instance is already being launched."
        case .replacementTerminatedDuringLaunch:
            "The replacement Cosmos instance terminated while launching."
        }
    }
}

final class WorkspaceApplicationRelauncher: ApplicationRelaunching {
    private var isLaunching = false

    func launchReplacement(
        waitingFor processID: pid_t,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !isLaunching else {
            completion(.failure(ApplicationRelaunchError.launchAlreadyInProgress))
            return
        }
        isLaunching = true

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = RelaunchArguments.make(
            handoff: RelaunchHandoff(previousProcessID: processID)
        )

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                self?.isLaunching = false
                if let error {
                    completion(.failure(error))
                    return
                }
                guard let application else {
                    completion(.failure(ApplicationRelaunchError.launchReturnedNoApplication))
                    return
                }
                guard !application.isTerminated else {
                    completion(.failure(ApplicationRelaunchError.replacementTerminatedDuringLaunch))
                    return
                }
                completion(.success(()))
            }
        }
    }
}

struct RelaunchHandoff: Equatable {
    let previousProcessID: pid_t
}

enum RelaunchArguments {
    private static let previousProcessFlag = "--relaunch-after-pid"

    static func make(handoff: RelaunchHandoff) -> [String] {
        [previousProcessFlag, String(handoff.previousProcessID)]
    }

    static func handoff(from arguments: [String]) -> RelaunchHandoff? {
        guard let flagIndex = arguments.firstIndex(of: previousProcessFlag),
              arguments.indices.contains(flagIndex + 1),
              let processID = pid_t(arguments[flagIndex + 1]),
              processID > 0
        else {
            return nil
        }
        return RelaunchHandoff(previousProcessID: processID)
    }
}

final class SetupRelaunchCoordinator {
    private let stateStore: OnboardingStateStore
    private let relauncher: any ApplicationRelaunching
    private let currentProcessID: () -> pid_t
    private let terminate: () -> Void
    private let onFailure: (Error) -> Void
    private var isRelaunching = false

    var relaunchInProgress: Bool {
        isRelaunching
    }

    init(
        stateStore: OnboardingStateStore,
        relauncher: any ApplicationRelaunching,
        currentProcessID: @escaping () -> pid_t = getpid,
        terminate: @escaping () -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        self.stateStore = stateStore
        self.relauncher = relauncher
        self.currentProcessID = currentProcessID
        self.terminate = terminate
        self.onFailure = onFailure
    }

    func relaunch() {
        guard !isRelaunching else {
            return
        }
        isRelaunching = true
        let previousCompletedVersion = stateStore.reset()
        relauncher.launchReplacement(waitingFor: currentProcessID()) { [weak self] result in
            self?.finish(result, previousCompletedVersion: previousCompletedVersion)
        }
    }

    private func finish(
        _ result: Result<Void, Error>,
        previousCompletedVersion: Int
    ) {
        switch result {
        case .success:
            terminate()
        case let .failure(error):
            stateStore.restoreCompletedVersion(previousCompletedVersion)
            isRelaunching = false
            onFailure(error)
        }
    }
}

enum CosmosApplication {
    static func run() {
        let app = NSApplication.shared
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            app.run()
            return
        }

        let runtimeHost = ApplicationRuntimeHost(
            makeRuntime: { AppCompositionRoot().build() },
            relaunchHandoff: RelaunchArguments.handoff(from: ProcessInfo.processInfo.arguments)
        )
        let appDelegate = AppDelegate(runtimeHost: runtimeHost)
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
