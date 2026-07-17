import CoreGraphics
@testable import KkaciCore
import XCTest

final class MonitorSlotResolverTests: XCTestCase {
    func testTopologyKeepsMirroredDisplayButDoesNotAssignItAMonitorSlot() {
        let provider = FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(
                id: 2,
                frame: CGRect(x: 1000, y: 200, width: 800, height: 600),
                role: .mirrored(source: 1)
            )
        ])
        let topology = MonitorSlotResolver(displayProvider: provider).topology()

        XCTAssertEqual(topology.displays.map(\.id), [1, 2])
        XCTAssertEqual(topology.displays[1].role, .mirrored(source: 1))
        XCTAssertEqual(topology.displays[1].frame, CGRect(x: 1000, y: 200, width: 800, height: 600))
        XCTAssertEqual(topology.monitorSlots.map(\.display.id), [1])
        XCTAssertEqual(provider.displayQueryCount, 1)
    }

    func testSlotsUseMainDisplayFirstThenDistanceFromMainDisplay() {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 10, frame: CGRect(x: 2000, y: 0, width: 1000, height: 1000), role: .extended),
            DisplaySnapshot(id: 20, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 30, frame: CGRect(x: -1000, y: 0, width: 1000, height: 1000), role: .extended)
        ]))

        XCTAssertEqual(resolver.slots().map(\.slot), [1, 2, 3])
        XCTAssertEqual(resolver.slots().map(\.display.id), [20, 30, 10])
    }

    func testWindowCenterSelectsContainingMonitorSlot() {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), role: .extended)
        ]))

        XCTAssertEqual(resolver.slot(containing: .frame(x: 1200, y: 100)), 2)
        XCTAssertEqual(resolver.slot(containing: .frame(x: 900, y: 100, width: 300, height: 100)), 2)
    }

    func testWindowCenterOutsideDisplaysFallsBackToNearestMonitorSlot() {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), role: .extended)
        ]))

        XCTAssertEqual(resolver.slot(containing: .frame(x: 2200, y: 100)), 2)
        XCTAssertEqual(resolver.slot(containing: nil), 1)
    }

    func testTranslatedFrameScalesFrameByTargetMonitorRatio() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 500, height: 500), role: .extended)
        ]))

        let translated = try XCTUnwrap(resolver.translatedFrame(.frame(x: 100, y: 120, width: 300, height: 200), to: 2))

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
            resolver.translatedFrame(.frame(x: 0, y: 100, width: 2000, height: 1900), to: 2)
        )

        XCTAssertEqual(translated.origin, CGPoint(x: 2000, y: 0))
        XCTAssertEqual(translated.size, CGSize(width: 1000, height: 1000))
    }

    func testTranslatedFrameClampsScaledFrameInsideTargetMonitor() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1000, height: 1000), role: .main),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1000, y: 0, width: 500, height: 500), role: .extended)
        ]))

        let translated = try XCTUnwrap(resolver.translatedFrame(.frame(x: 800, y: 800, width: 300, height: 300), to: 2))

        XCTAssertEqual(translated.origin, CGPoint(x: 1350, y: 350))
        XCTAssertEqual(translated.size, CGSize(width: 150, height: 150))
    }
}
