import CoreGraphics
@testable import CosmosCore
import XCTest

final class MonitorSlotResolverTests: XCTestCase {
    func testResolverMapsDisplayIDToMonitorSlot() throws {
        let monitorSlots = [
            MonitorSlotSnapshot(
                slot: 1,
                display: DisplaySnapshot(id: 10, frame: .zero, role: .main)
            ),
            MonitorSlotSnapshot(
                slot: 2,
                display: DisplaySnapshot(id: 20, frame: .zero, role: .extended)
            )
        ]

        XCTAssertEqual(
            try DisplayTopologySnapshot(monitorSlots: monitorSlots).monitorSlot(for: 20),
            2
        )
    }

    func testResolverRejectsUnknownDisplay() {
        let monitorSlots = [
            MonitorSlotSnapshot(
                slot: 1,
                display: DisplaySnapshot(id: 10, frame: .zero, role: .main)
            )
        ]

        XCTAssertThrowsError(
            try DisplayTopologySnapshot(monitorSlots: monitorSlots).monitorSlot(for: 20)
        ) { error in
            XCTAssertEqual(error as? SpaceError, .displayNotFound(20))
        }
    }

    func testSlotsUseMainDisplayFirstThenDistanceFromMainDisplay() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 10, frame: CGRect(x: 2000, y: 0, width: 1000, height: 1000), role: .extended),
            DisplaySnapshot(id: 20, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 30, frame: CGRect(x: -1000, y: 0, width: 1000, height: 1000), role: .extended)
        ]))

        let slots = try resolver.topology().monitorSlots
        XCTAssertEqual(slots.map(\.slot), [1, 2, 3])
        XCTAssertEqual(slots.map(\.display.id), [20, 30, 10])
    }

    func testWindowCenterSelectsContainingMonitorSlot() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), role: .extended)
        ]))

        let slots = try resolver.topology().monitorSlots
        XCTAssertEqual(resolver.slot(containing: .frame(x: 1200, y: 100), among: slots), 2)
        XCTAssertEqual(resolver.slot(containing: .frame(x: 900, y: 100, width: 300, height: 100), among: slots), 2)
    }

    func testWindowCenterOutsideDisplaysFallsBackToNearestMonitorSlot() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), role: .extended)
        ]))

        let slots = try resolver.topology().monitorSlots
        XCTAssertEqual(resolver.slot(containing: .frame(x: 2200, y: 100), among: slots), 2)
        XCTAssertEqual(resolver.slot(containing: nil, among: slots), 1)
    }

    func testTranslatedFrameScalesFrameByTargetMonitorRatio() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 500, height: 500), role: .extended)
        ]))

        let translated = try XCTUnwrap(try resolver.translatedFrame(
            .frame(x: 100, y: 120, width: 300, height: 200),
            to: 2,
            among: resolver.topology().monitorSlots
        ))

        XCTAssertEqual(translated.origin, CGPoint(x: 1050, y: 60))
        XCTAssertEqual(translated.size, CGSize(width: 150, height: 100))
    }

    func testTranslatedFrameUsesVisibleFrameForRatio() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 2000, height: 2000),
                visibleFrame: CGRect(x: 0, y: 100, width: 2000, height: 1900),
                role: .main
            ),
            DisplaySnapshot(
                id: 2,
                frame: CGRect(x: 2000, y: 0, width: 1000, height: 1000),
                visibleFrame: CGRect(x: 2000, y: 0, width: 1000, height: 1000),
                role: .extended
            )
        ]))

        let translated = try XCTUnwrap(
            try resolver.translatedFrame(
                .frame(x: 0, y: 100, width: 2000, height: 1900),
                to: 2,
                among: resolver.topology().monitorSlots
            )
        )

        XCTAssertEqual(translated.origin, CGPoint(x: 2000, y: 0))
        XCTAssertEqual(translated.size, CGSize(width: 1000, height: 1000))
    }

    func testTranslatedFrameClampsScaledFrameInsideTargetMonitor() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 500, height: 500), role: .extended)
        ]))

        let translated = try XCTUnwrap(try resolver.translatedFrame(
            .frame(x: 800, y: 800, width: 300, height: 300),
            to: 2,
            among: resolver.topology().monitorSlots
        ))

        XCTAssertEqual(translated.origin, CGPoint(x: 1350, y: 350))
        XCTAssertEqual(translated.size, CGSize(width: 150, height: 150))
    }
}
