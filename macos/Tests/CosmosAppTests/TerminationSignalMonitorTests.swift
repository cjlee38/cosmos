@testable import CosmosApp
import Darwin
import XCTest

final class TerminationSignalMonitorTests: XCTestCase {
    func testSignalRestoresBeforeTerminatingWithReceivedSignal() {
        var events: [String] = []
        let monitor = TerminationSignalMonitor(
            recover: {
                events.append("recover")
            },
            terminate: { signalNumber in
                events.append("terminate:\(signalNumber)")
            }
        )

        monitor.handle(SIGINT)

        XCTAssertEqual(events, ["recover", "terminate:\(SIGINT)"])
    }

    func testOnlyFirstSignalIsHandled() {
        var handledSignals: [Int32] = []
        let monitor = TerminationSignalMonitor(
            recover: {},
            terminate: { handledSignals.append($0) }
        )

        monitor.handle(SIGINT)
        monitor.handle(SIGTERM)

        XCTAssertEqual(handledSignals, [SIGINT])
    }
}
