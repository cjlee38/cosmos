import AppKit
@testable import CosmosApp
import XCTest

final class ApplicationIconCacheTests: XCTestCase {
    func testCompletedLoadDoesNotRestoreAnIconForARemovedProcess() {
        let loadStarted = expectation(description: "icon load started")
        let loadFinished = expectation(description: "icon load finished")
        let allowLoadToFinish = DispatchSemaphore(value: 0)
        let cache = ApplicationIconCache { _ in
            loadStarted.fulfill()
            allowLoadToFinish.wait()
            loadFinished.fulfill()
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        var updatedPIDs: [pid_t] = []
        cache.setUpdateHandler { updatedPIDs.append($0) }

        cache.refresh(pids: [42])
        wait(for: [loadStarted], timeout: 1)
        cache.refresh(pids: [])
        allowLoadToFinish.signal()
        wait(for: [loadFinished], timeout: 1)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNil(cache.icon(for: 42))
        XCTAssertTrue(updatedPIDs.isEmpty)
    }
}
