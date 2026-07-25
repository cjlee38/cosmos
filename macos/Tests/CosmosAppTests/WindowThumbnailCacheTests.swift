@testable import CosmosApp
import CosmosCore
import Foundation
import XCTest

final class WindowThumbnailCacheTests: XCTestCase {
    func testRefreshRecapturesOnlyAfterThumbnailExpires() {
        let lock = NSLock()
        var captureCount = 0
        var now: TimeInterval = 0
        let firstCapture = expectation(description: "first capture")
        let expiredCapture = expectation(description: "expired capture")
        let cache = WindowThumbnailCache(
            captureImage: { _ in
                lock.lock()
                captureCount += 1
                lock.unlock()
                return makeSwitcherTestImage()
            },
            canCapture: { true },
            maximumAge: 2,
            currentTime: { now }
        )
        var updateCount = 0
        cache.setUpdateHandler { _ in
            updateCount += 1
            if updateCount == 1 {
                firstCapture.fulfill()
            } else if updateCount == 2 {
                expiredCapture.fulfill()
            }
        }
        cache.removeStaleThumbnails(keeping: [100])

        cache.refresh(windowIDs: [100])
        wait(for: [firstCapture], timeout: 1)

        now = 1
        cache.refresh(windowIDs: [100])
        lock.lock()
        XCTAssertEqual(captureCount, 1)
        lock.unlock()

        now = 2
        cache.refresh(windowIDs: [100])
        wait(for: [expiredCapture], timeout: 1)
        lock.lock()
        XCTAssertEqual(captureCount, 2)
        lock.unlock()
    }
}
