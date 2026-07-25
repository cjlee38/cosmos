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

    func testFailedCapturePreservesThumbnailAndRetries() {
        var captureCount = 0
        var now: TimeInterval = 0
        let firstCapture = expectation(description: "first capture")
        let failedCapture = expectation(description: "failed capture")
        let retryCapture = expectation(description: "retry capture")
        let image = makeSwitcherTestImage()
        let cache = WindowThumbnailCache(
            captureImages: { windowIDs, completion in
                captureCount += 1
                let currentCapture = captureCount

                for windowID in windowIDs {
                    switch currentCapture {
                    case 1:
                        completion(windowID, .success(image))
                    case 2:
                        completion(windowID, .failure(NSError(domain: "test", code: 1)))
                        DispatchQueue.main.async {
                            failedCapture.fulfill()
                        }
                    default:
                        completion(windowID, .success(image))
                    }
                }
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
                retryCapture.fulfill()
            }
        }
        cache.removeStaleThumbnails(keeping: [100])

        cache.refresh(windowIDs: [100])
        wait(for: [firstCapture], timeout: 1)
        XCTAssertNotNil(cache.thumbnail(for: 100))

        now = 2
        cache.refresh(windowIDs: [100])
        wait(for: [failedCapture], timeout: 1)
        XCTAssertNotNil(cache.thumbnail(for: 100))

        cache.refresh(windowIDs: [100])
        wait(for: [retryCapture], timeout: 1)
        XCTAssertEqual(captureCount, 3)
    }
}
