import Darwin
import Dispatch

final class TerminationSignalMonitor {
    private let signals: [Int32]
    private let recover: () -> Void
    private let terminate: (Int32) -> Void
    private var sources: [DispatchSourceSignal] = []
    private var didHandleSignal = false

    init(
        signals: [Int32] = [SIGINT, SIGTERM],
        recover: @escaping () -> Void,
        terminate: @escaping (Int32) -> Void = TerminationSignalMonitor.terminate
    ) {
        self.signals = signals
        self.recover = recover
        self.terminate = terminate
    }

    func start() {
        guard sources.isEmpty else {
            return
        }

        sources = signals.map { signalNumber in
            Darwin.signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.handle(signalNumber)
            }
            source.activate()
            return source
        }
    }

    func handle(_ signalNumber: Int32) {
        guard !didHandleSignal else {
            return
        }
        didHandleSignal = true
        recover()
        terminate(signalNumber)
    }

    private static func terminate(_ signalNumber: Int32) {
        Darwin.signal(signalNumber, SIG_DFL)
        Darwin.kill(Darwin.getpid(), signalNumber)
    }
}
