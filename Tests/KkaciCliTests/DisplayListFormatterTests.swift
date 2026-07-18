import CoreGraphics
@testable import KkaciCli
import KkaciCore
import XCTest

final class DisplayListFormatterTests: XCTestCase {
    func testLinesAreSortedByMonitorSlotAndIncludeDisplayRole() {
        let topology = DisplayTopologySnapshot(monitorSlots: [
            MonitorSlotSnapshot(
                slot: 2,
                display: DisplaySnapshot(
                    id: 20,
                    name: "Built-in Retina Display",
                    frame: .zero,
                    role: .extended
                )
            ),
            MonitorSlotSnapshot(
                slot: 1,
                display: DisplaySnapshot(
                    id: 10,
                    name: "LG ULTRAFINE",
                    frame: .zero,
                    role: .main
                )
            )
        ])

        XCTAssertEqual(DisplayListFormatter.lines(for: topology), [
            "1 (LG ULTRAFINE)  Main",
            "2 (Built-in Retina Display)  Extended"
        ])
    }

    func testEmptyTopologyProducesNoLines() {
        XCTAssertEqual(DisplayListFormatter.lines(for: .empty), [])
    }
}
