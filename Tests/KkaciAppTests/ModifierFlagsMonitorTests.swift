import CoreGraphics
@testable import KkaciApp
import XCTest

final class ModifierFlagsMonitorTests: XCTestCase {
    func testStartRequestsListenEventAccessBeforeCreatingTheTap() {
        var requestCount = 0
        let monitor = ModifierFlagsMonitor(
            onModifiersChanged: { _ in },
            ensureListenEventAccess: {
                requestCount += 1
                return false
            }
        )

        XCTAssertThrowsError(try monitor.start())
        XCTAssertEqual(requestCount, 1)
    }

    func testDisabledTapPublishesCurrentModifierStateAfterReenabling() throws {
        let modifiersPublished = expectation(description: "current modifiers published")
        var receivedModifiers: UInt32?
        let monitor = ModifierFlagsMonitor(
            onModifiersChanged: { modifiers in
                receivedModifiers = modifiers
                modifiersPublished.fulfill()
            },
            currentModifierFlags: { [] }
        )
        let event = try XCTUnwrap(CGEvent(source: nil))

        monitor.handle(type: .tapDisabledByTimeout, event: event)

        wait(for: [modifiersPublished], timeout: 1)
        XCTAssertEqual(receivedModifiers, 0)
    }
}
