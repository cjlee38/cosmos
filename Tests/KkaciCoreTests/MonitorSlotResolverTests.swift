import CoreGraphics
@testable import KkaciCore
import XCTest

final class MonitorSlotResolverTests: XCTestCase {
    func testSlotsUseMainDisplayFirstThenDistanceFromMainDisplay() {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 10, frame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000), isMain: false),
            DisplaySnapshot(id: 20, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
            DisplaySnapshot(id: 30, frame: CGRect(x: -1_000, y: 0, width: 1_000, height: 1_000), isMain: false),
        ]))

        XCTAssertEqual(resolver.slots().map(\.slot), [1, 2, 3])
        XCTAssertEqual(resolver.slots().map(\.display.id), [20, 30, 10])
    }

    func testWindowCenterSelectsContainingMonitorSlot() {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000), isMain: false),
        ]))

        XCTAssertEqual(resolver.slot(containing: .frame(x: 1_200, y: 100)), 2)
        XCTAssertEqual(resolver.slot(containing: .frame(x: 900, y: 100, width: 300, height: 100)), 2)
    }

    func testWindowCenterOutsideDisplaysFallsBackToNearestMonitorSlot() {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1_000, y: 0, width: 1_000, height: 1_000), isMain: false),
        ]))

        XCTAssertEqual(resolver.slot(containing: .frame(x: 2_200, y: 100)), 2)
        XCTAssertEqual(resolver.slot(containing: nil), 1)
    }

    func testTranslatedFrameScalesFrameByTargetMonitorRatio() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1_000, y: 0, width: 500, height: 500), isMain: false),
        ]))

        let translated = try XCTUnwrap(resolver.translatedFrame(.frame(x: 100, y: 120, width: 300, height: 200), to: 2))

        XCTAssertEqual(translated.origin, CGPoint(x: 1_050, y: 60))
        XCTAssertEqual(translated.size, CGSize(width: 150, height: 100))
    }

    func testTranslatedFrameUsesVisibleFrameForRatio() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 2_000, height: 2_000),
                visibleFrame: CGRect(x: 0, y: 100, width: 2_000, height: 1_900),
                isMain: true
            ),
            DisplaySnapshot(
                id: 2,
                frame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000),
                visibleFrame: CGRect(x: 2_000, y: 0, width: 1_000, height: 1_000),
                isMain: false
            ),
        ]))

        let translated = try XCTUnwrap(
            resolver.translatedFrame(.frame(x: 0, y: 100, width: 2_000, height: 1_900), to: 2)
        )

        XCTAssertEqual(translated.origin, CGPoint(x: 2_000, y: 0))
        XCTAssertEqual(translated.size, CGSize(width: 1_000, height: 1_000))
    }

    func testTranslatedFrameClampsScaledFrameInsideTargetMonitor() throws {
        let resolver = MonitorSlotResolver(displayProvider: FakeDisplayProvider(snapshots: [
            DisplaySnapshot(id: 1, frame: CGRect(x: 0, y: 0, width: 1_000, height: 1_000), isMain: true),
            DisplaySnapshot(id: 2, frame: CGRect(x: 1_000, y: 0, width: 500, height: 500), isMain: false),
        ]))

        let translated = try XCTUnwrap(resolver.translatedFrame(.frame(x: 800, y: 800, width: 300, height: 300), to: 2))

        XCTAssertEqual(translated.origin, CGPoint(x: 1_350, y: 350))
        XCTAssertEqual(translated.size, CGSize(width: 150, height: 150))
    }
}
