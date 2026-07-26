import ApplicationServices
@testable import CosmosApp
import CosmosCore
import XCTest

final class WindowRuntimeEventTests: XCTestCase {
    func testEventBufferDeduplicatesEventsIntoOneDelivery() {
        let event = WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(event)
        buffer.append(event)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertFalse(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
        XCTAssertNil(buffer.takeDelivery())
    }

    func testEventBufferDefersDeliveryUntilWindowDragEnds() {
        let event = WindowRuntimeEvent(kind: .layoutChanged, windowID: 100)
        var buffer = WindowRuntimeEventBuffer()

        buffer.beginWindowDrag()
        buffer.append(event)

        XCTAssertFalse(buffer.reserveDelivery())
        buffer.endWindowDrag()
        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
    }

    func testEventBufferKeepsReservedEventsWhenDragStartsBeforeDelivery() {
        let event = WindowRuntimeEvent(kind: .layoutChanged, windowID: 100)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(event)
        XCTAssertTrue(buffer.reserveDelivery())
        buffer.beginWindowDrag()

        XCTAssertNil(buffer.takeDelivery())
        buffer.endWindowDrag()
        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
    }

    func testEventBufferDiscardsPendingAndIncomingEventsWhileSessionIsInactive() {
        let pending = WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        let inactive = WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(pending)
        XCTAssertTrue(buffer.reserveDelivery())
        buffer.suspend()
        buffer.append(inactive)

        XCTAssertNil(buffer.takeDelivery())
        XCTAssertTrue(buffer.events.isEmpty)
    }

    func testEventBufferDeliversFreshSyncAfterSessionBecomesActive() {
        let freshSync = WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.suspend()
        buffer.resume()
        buffer.append(freshSync)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [freshSync])
    }

    func testResizeRequiresLayoutSyncAndThumbnailCapture() {
        let kinds = WindowRuntimeEventKind.kinds(
            forAXNotification: kAXWindowResizedNotification as String
        )
        let batch = WindowRuntimeEventBatch(events: Set(kinds.map { kind in
            WindowRuntimeEvent(kind: kind, windowID: 100)
        }))

        XCTAssertEqual(kinds, [.layoutChanged, .thumbnailChanged])
        XCTAssertEqual(batch.windowIDsNeedingCapture, [100])
    }

    func testDisplayChangeIsRecognizedAsTopologyAndFullThumbnailChange() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .displayChanged, windowID: nil)
        ])

        XCTAssertTrue(batch.containsDisplayChange)
        XCTAssertTrue(batch.needsFullThumbnailRefresh)
    }

    func testCreatedWindowRequiresFullDiscovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 100),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: 100)
        ])

        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeRequiresFullDiscovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil)
        ])

        XCTAssertTrue(batch.containsSessionResume)
        XCTAssertTrue(batch.isSessionResumeRecovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeMixedWithWindowSetChangeIsNotRecoveryOnly() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ])

        XCTAssertFalse(batch.isSessionResumeRecovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeMixedWithFocusChangeRemainsRecovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ])

        XCTAssertTrue(batch.isSessionResumeRecovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testExistingWindowChangesDiscoverOnlyAffectedWindows() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 100),
            WindowRuntimeEvent(kind: .thumbnailChanged, windowID: 200)
        ])

        XCTAssertEqual(batch.discoveryWindowIDs, [100, 200])
    }

    func testEventKindsPreserveDistinctFocusLayoutAndThumbnailSemantics() {
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXFocusedWindowChangedNotification as String),
            [.focusChanged]
        )
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXWindowMovedNotification as String),
            [.layoutChanged]
        )
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXUIElementDestroyedNotification as String),
            [.windowDestroyed]
        )
        XCTAssertEqual(
            WindowRuntimeEventKind.kinds(forAXNotification: kAXTitleChangedNotification as String),
            [.thumbnailChanged]
        )
    }

    func testApplicationActivationAndAXFocusChangeRemainDistinct() {
        let activation = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .applicationActivated, windowID: nil)
        ])
        let axFocus = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ])

        XCTAssertTrue(activation.containsApplicationActivation)
        XCTAssertTrue(activation.containsFocusChange)
        XCTAssertFalse(axFocus.containsApplicationActivation)
        XCTAssertTrue(axFocus.containsFocusChange)
    }
}
