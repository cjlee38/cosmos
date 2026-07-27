@testable import CosmosCore
import XCTest

final class PanicTests: XCTestCase {
    func testRecoveryRunsOnMainThread() {
        var recoveryRan = false
        PanicRecovery.install {
            XCTAssertTrue(Thread.isMainThread)
            recoveryRan = true
        }

        PanicRecovery.perform()

        XCTAssertTrue(recoveryRan)
    }

    func testBackgroundPanicWaitsForRecoveryOnMainThread() {
        let recoveryRan = expectation(description: "recovery ran")
        PanicRecovery.install {
            XCTAssertTrue(Thread.isMainThread)
            recoveryRan.fulfill()
        }

        DispatchQueue.global().async {
            PanicRecovery.perform()
        }

        wait(for: [recoveryRan], timeout: 1)
    }

    func testBackgroundPanicDoesNotWaitIndefinitelyForMainThread() {
        let performReturned = expectation(description: "perform returned")
        let performStarted = DispatchSemaphore(value: 0)
        PanicRecovery.install {}

        DispatchQueue.global().async {
            performStarted.signal()
            PanicRecovery.perform(offMainTimeout: .milliseconds(10))
            performReturned.fulfill()
        }
        performStarted.wait()
        Thread.sleep(forTimeInterval: 0.05)

        wait(for: [performReturned], timeout: 1)
    }
}
