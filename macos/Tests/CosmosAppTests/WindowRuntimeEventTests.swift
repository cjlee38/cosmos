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

        buffer.beginWindowDrag(windowID: 100)
        buffer.append(event)

        XCTAssertFalse(buffer.reserveDelivery())
        buffer.endWindowDrag()
        XCTAssertTrue(buffer.reserveDelivery())
        let delivered = buffer.takeDelivery()
        XCTAssertEqual(delivered, [
            WindowRuntimeEvent(kind: .userLayoutChanged, windowID: 100)
        ])
        XCTAssertEqual(
            delivered.map { WindowRuntimeEventBatch(events: $0) }?.userMovedWindowIDs,
            [100]
        )
    }

    func testEventBufferDoesNotRelabelEarlierSystemLayoutWhenDragStartsBeforeDelivery() {
        let systemLayout = WindowRuntimeEvent(kind: .layoutChanged, windowID: 100)
        let userLayout = WindowRuntimeEvent(kind: .layoutChanged, windowID: 200)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(systemLayout)
        XCTAssertTrue(buffer.reserveDelivery())
        buffer.beginWindowDrag(windowID: 200)
        buffer.append(userLayout)
        buffer.append(WindowRuntimeEvent(kind: .layoutChanged, windowID: 300))

        XCTAssertNil(buffer.takeDelivery())
        buffer.endWindowDrag()
        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [
            systemLayout,
            WindowRuntimeEvent(kind: .userLayoutChanged, windowID: 200),
            WindowRuntimeEvent(kind: .layoutChanged, windowID: 300)
        ])
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

        XCTAssertTrue(batch.containsRecoveryRequest)
        XCTAssertTrue(batch.usesSessionRecoveryDiscovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeMixedWithWindowSetChangeIsNotRecoveryOnly() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        ])

        XCTAssertFalse(batch.usesSessionRecoveryDiscovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testSessionResumeMixedWithFocusChangeRemainsRecovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .sessionResumed, windowID: nil),
            WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        ])

        XCTAssertTrue(batch.usesSessionRecoveryDiscovery)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testContinuityRecoveryRequiresDisplayRecoveryDiscovery() {
        let batch = WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .continuityRecovery, windowID: nil)
        ])

        XCTAssertTrue(batch.containsDisplayChange)
        XCTAssertTrue(batch.containsRecoveryRequest)
        XCTAssertTrue(batch.usesSessionRecoveryDiscovery)
        XCTAssertTrue(batch.needsFullThumbnailRefresh)
        XCTAssertNil(batch.discoveryWindowIDs)
    }

    func testEventBufferRemainsSuspendedUntilSessionAndSleepRecover() {
        let event = WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.suspend(.userSession)
        buffer.suspend(.systemSleep)
        buffer.resume(.systemSleep)
        buffer.append(event)

        XCTAssertFalse(buffer.reserveDelivery())

        buffer.resume(.userSession)
        buffer.append(event)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
    }

    func testEventBufferRetainsLifecycleAndDisplayEvidenceWhileSuspended() {
        let focus = WindowRuntimeEvent(kind: .focusChanged, windowID: 100)
        let destroyed = WindowRuntimeEvent(kind: .windowDestroyed, windowID: 200)
        let terminated = WindowRuntimeEvent(kind: .applicationTerminated, windowID: nil, processID: 42)
        let display = WindowRuntimeEvent(kind: .displayChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.append(focus)
        buffer.append(destroyed)
        buffer.suspend(.systemSleep)
        buffer.append(terminated)
        buffer.append(display)
        buffer.resume(.systemSleep)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [destroyed, terminated, display])
    }

    func testEventBufferWaitsForScreenLockAndSleepToBothResume() {
        let event = WindowRuntimeEvent(kind: .windowSetChanged, windowID: nil)
        var buffer = WindowRuntimeEventBuffer()

        buffer.suspend(.screenLock)
        buffer.suspend(.systemSleep)
        buffer.resume(.screenLock)
        buffer.append(event)

        XCTAssertFalse(buffer.reserveDelivery())

        buffer.resume(.systemSleep)
        buffer.append(event)

        XCTAssertTrue(buffer.reserveDelivery())
        XCTAssertEqual(buffer.takeDelivery(), [event])
    }

    func testObservationStateBeginsProtectionOnlyForFirstSuspensionReason() {
        var state = WindowObservationState()

        let lock = state.set(.screenLock, isSuspended: true)
        let sleep = state.set(.systemSleep, isSuspended: true)
        let unlock = state.set(.screenLock, isSuspended: false)
        let wake = state.set(.systemSleep, isSuspended: false)

        XCTAssertEqual(lock?.beganSuspension, true)
        XCTAssertEqual(sleep?.beganSuspension, false)
        XCTAssertEqual(unlock?.isActive, false)
        XCTAssertEqual(wake?.isActive, true)
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
