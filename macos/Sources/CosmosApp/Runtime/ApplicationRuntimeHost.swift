import AppKit
import Darwin

protocol ApplicationRuntimeLifecycle: AnyObject {
    func start()
    func shutdown()
}

extension AppRuntime: ApplicationRuntimeLifecycle {}

final class ProcessTerminationObservation {
    private var application: NSRunningApplication?
    private var observation: NSKeyValueObservation?
    private let invalidateHandler: (() -> Void)?
    private var isInvalidated = false

    init(invalidate: @escaping () -> Void = {}) {
        invalidateHandler = invalidate
    }

    static func observe(
        application: NSRunningApplication,
        onTermination: @escaping () -> Void
    ) -> ProcessTerminationObservation {
        let terminationObservation = ProcessTerminationObservation()
        terminationObservation.application = application
        terminationObservation.observation = application.observe(
            \.isTerminated,
            options: [.initial, .new]
        ) { [weak terminationObservation] application, _ in
            guard application.isTerminated else {
                return
            }
            DispatchQueue.main.async {
                guard terminationObservation?.isInvalidated == false else {
                    return
                }
                onTermination()
            }
        }
        return terminationObservation
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        observation?.invalidate()
        observation = nil
        application = nil
        invalidateHandler?()
    }
}

final class ApplicationRuntimeHost {
    private let makeRuntime: () -> any ApplicationRuntimeLifecycle
    private let relaunchHandoff: RelaunchHandoff?
    private let observeProcessTermination: (
        pid_t,
        @escaping () -> Void
    ) -> ProcessTerminationObservation?
    private var runtime: (any ApplicationRuntimeLifecycle)?
    private var previousProcessTerminationObservation: ProcessTerminationObservation?
    private var isShuttingDown = false

    init(
        makeRuntime: @escaping () -> any ApplicationRuntimeLifecycle,
        relaunchHandoff: RelaunchHandoff?,
        observeProcessTermination: @escaping (
            pid_t,
            @escaping () -> Void
        ) -> ProcessTerminationObservation? = ApplicationRuntimeHost.observeProcessTermination
    ) {
        self.makeRuntime = makeRuntime
        self.relaunchHandoff = relaunchHandoff
        self.observeProcessTermination = observeProcessTermination
    }

    func start() {
        guard !isShuttingDown else {
            return
        }
        guard let relaunchHandoff else {
            startRuntime()
            return
        }
        previousProcessTerminationObservation = observeProcessTermination(
            relaunchHandoff.previousProcessID,
            { [weak self] in self?.previousProcessDidExit() }
        )
        if previousProcessTerminationObservation == nil {
            startRuntime()
        }
    }

    func shutdown() {
        guard !isShuttingDown else {
            return
        }
        isShuttingDown = true
        stopWaitingForPreviousProcess()
        runtime?.shutdown()
    }

    private func previousProcessDidExit() {
        guard !isShuttingDown else {
            return
        }
        stopWaitingForPreviousProcess()
        startRuntime()
    }

    private func stopWaitingForPreviousProcess() {
        previousProcessTerminationObservation?.invalidate()
        previousProcessTerminationObservation = nil
    }

    private func startRuntime() {
        guard !isShuttingDown, runtime == nil else {
            return
        }
        let runtime = makeRuntime()
        self.runtime = runtime
        runtime.start()
    }

    private static func observeProcessTermination(
        processID: pid_t,
        onTermination: @escaping () -> Void
    ) -> ProcessTerminationObservation? {
        guard let application = NSRunningApplication(processIdentifier: processID),
              application.bundleURL?.resolvingSymlinksInPath()
              == Bundle.main.bundleURL.resolvingSymlinksInPath()
        else {
            return nil
        }
        return ProcessTerminationObservation.observe(
            application: application,
            onTermination: onTermination
        )
    }
}
