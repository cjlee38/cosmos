@testable import CosmosApp
import XCTest

final class AppProfileTests: XCTestCase {
    func testDebugAndReleaseProfilesUseSeparateDataDirectories() {
        let homeDirectory = URL(fileURLWithPath: "/Users/test")
        let applicationSupportDirectory = URL(fileURLWithPath: "/Users/test/Library/Application Support")

        XCTAssertEqual(
            AppProfile.debug.configURL(homeDirectory: homeDirectory).path,
            "/Users/test/.config/cosmos-dev/config.yaml"
        )
        XCTAssertEqual(
            AppProfile.release.configURL(homeDirectory: homeDirectory).path,
            "/Users/test/.config/cosmos/config.yaml"
        )
        XCTAssertEqual(
            AppProfile.debug.sessionStateURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/cosmos-dev/session-state.json"
        )
        XCTAssertEqual(
            AppProfile.release.sessionStateURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/cosmos/session-state.json"
        )
    }

    func testCurrentProfileUsesDebugDataDuringDebugBuilds() {
        #if DEBUG
            XCTAssertEqual(AppProfile.current, .debug)
        #else
            XCTAssertEqual(AppProfile.current, .release)
        #endif
    }
}

final class AppRuntimeStartupTests: XCTestCase {
    func testOnboardingDoesNotStartManagedRuntime() {
        var onboardingCount = 0
        var managedRuntimeCount = 0

        AppRuntimeStartup.run(
            requiresOnboarding: true,
            showOnboarding: { onboardingCount += 1 },
            startManagedRuntime: { managedRuntimeCount += 1 }
        )

        XCTAssertEqual(onboardingCount, 1)
        XCTAssertEqual(managedRuntimeCount, 0)
    }

    func testCompletedOnboardingStartsManagedRuntime() {
        var onboardingCount = 0
        var managedRuntimeCount = 0

        AppRuntimeStartup.run(
            requiresOnboarding: false,
            showOnboarding: { onboardingCount += 1 },
            startManagedRuntime: { managedRuntimeCount += 1 }
        )

        XCTAssertEqual(onboardingCount, 0)
        XCTAssertEqual(managedRuntimeCount, 1)
    }
}

final class RelaunchArgumentsTests: XCTestCase {
    func testRelaunchArgumentsRoundTripHandoff() {
        let handoff = RelaunchHandoff(previousProcessID: 1234)
        let arguments = ["Cosmos"] + RelaunchArguments.make(handoff: handoff)

        XCTAssertEqual(RelaunchArguments.handoff(from: arguments), handoff)
    }

    func testRelaunchArgumentsRejectMissingInvalidAndNonPositiveProcessIDs() {
        XCTAssertNil(RelaunchArguments.handoff(from: ["Cosmos"]))
        XCTAssertNil(RelaunchArguments.handoff(from: ["Cosmos", "--relaunch-after-pid"]))
        XCTAssertNil(RelaunchArguments.handoff(
            from: ["Cosmos", "--relaunch-after-pid", "invalid"]
        ))
        XCTAssertNil(RelaunchArguments.handoff(
            from: ["Cosmos", "--relaunch-after-pid", "0"]
        ))
    }
}

final class SetupRelaunchCoordinatorTests: XCTestCase {
    func testSuccessResetsStateSuppressesDuplicatesAndTerminates() throws {
        let suiteName = "SetupRelaunchCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7, forKey: "onboarding.completedVersion")
        let relauncher = ApplicationRelauncherSpy()
        var didTerminate = false
        let coordinator = SetupRelaunchCoordinator(
            stateStore: OnboardingStateStore(defaults: defaults),
            relauncher: relauncher,
            currentProcessID: { 42 },
            terminate: { didTerminate = true },
            onFailure: { _ in XCTFail("Unexpected relaunch failure") }
        )

        coordinator.relaunch()
        coordinator.relaunch()

        XCTAssertTrue(coordinator.relaunchInProgress)
        XCTAssertEqual(defaults.integer(forKey: "onboarding.completedVersion"), 0)
        XCTAssertEqual(relauncher.processIDs, [42])
        XCTAssertFalse(didTerminate)

        relauncher.complete(.success(()))

        XCTAssertTrue(didTerminate)
    }

    func testFailureRestoresExactStateAndAllowsRetry() throws {
        let suiteName = "SetupRelaunchCoordinatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7, forKey: "onboarding.completedVersion")
        let relauncher = ApplicationRelauncherSpy()
        var failures: [Error] = []
        let coordinator = SetupRelaunchCoordinator(
            stateStore: OnboardingStateStore(defaults: defaults),
            relauncher: relauncher,
            currentProcessID: { 42 },
            terminate: { XCTFail("Failed relaunch must not terminate") },
            onFailure: { failures.append($0) }
        )

        coordinator.relaunch()
        relauncher.complete(.failure(SetupRelaunchTestError.failed))

        XCTAssertFalse(coordinator.relaunchInProgress)
        XCTAssertEqual(defaults.integer(forKey: "onboarding.completedVersion"), 7)
        XCTAssertEqual(failures.count, 1)

        coordinator.relaunch()

        XCTAssertEqual(relauncher.processIDs, [42, 42])
    }
}

final class ApplicationRuntimeHostTests: XCTestCase {
    func testReplacementWaitsForPreviousProcessExitBeforeStartingRuntime() {
        let runtime = ApplicationRuntimeLifecycleSpy()
        var observedProcessID: pid_t?
        var processDidExit: (() -> Void)?
        var observationWasInvalidated = false
        let host = ApplicationRuntimeHost(
            makeRuntime: { runtime },
            relaunchHandoff: RelaunchHandoff(previousProcessID: 42),
            observeProcessTermination: { processID, onExit in
                observedProcessID = processID
                processDidExit = onExit
                return ProcessTerminationObservation(
                    invalidate: { observationWasInvalidated = true }
                )
            }
        )

        host.start()

        XCTAssertEqual(observedProcessID, 42)
        XCTAssertEqual(runtime.startCount, 0)

        processDidExit?()

        XCTAssertTrue(observationWasInvalidated)
        XCTAssertEqual(runtime.startCount, 1)
    }

    func testReplacementStartsImmediatelyWhenPreviousProcessAlreadyExited() {
        let runtime = ApplicationRuntimeLifecycleSpy()
        var didObserveProcess = false
        let host = ApplicationRuntimeHost(
            makeRuntime: { runtime },
            relaunchHandoff: RelaunchHandoff(previousProcessID: 42),
            observeProcessTermination: { _, _ in
                didObserveProcess = true
                return nil
            }
        )

        host.start()

        XCTAssertEqual(runtime.startCount, 1)
        XCTAssertTrue(didObserveProcess)
    }

    func testShutdownInvalidatesWaitAndIgnoresLaterTermination() {
        let runtime = ApplicationRuntimeLifecycleSpy()
        var processDidExit: (() -> Void)?
        var observationWasInvalidated = false
        let host = ApplicationRuntimeHost(
            makeRuntime: { runtime },
            relaunchHandoff: RelaunchHandoff(previousProcessID: 42),
            observeProcessTermination: { _, onExit in
                processDidExit = onExit
                return ProcessTerminationObservation(
                    invalidate: { observationWasInvalidated = true }
                )
            }
        )

        host.start()
        host.shutdown()
        processDidExit?()

        XCTAssertTrue(observationWasInvalidated)
        XCTAssertEqual(runtime.startCount, 0)
    }
}

private enum SetupRelaunchTestError: Error {
    case failed
}

private final class ApplicationRelauncherSpy: ApplicationRelaunching {
    private var completion: ((Result<Void, Error>) -> Void)?
    private(set) var processIDs: [pid_t] = []

    func launchReplacement(
        waitingFor processID: pid_t,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        processIDs.append(processID)
        self.completion = completion
    }

    func complete(_ result: Result<Void, Error>) {
        let completion = completion
        self.completion = nil
        completion?(result)
    }
}

private final class ApplicationRuntimeLifecycleSpy: ApplicationRuntimeLifecycle {
    private(set) var startCount = 0
    private(set) var shutdownCount = 0

    func start() {
        startCount += 1
    }

    func shutdown() {
        shutdownCount += 1
    }
}
