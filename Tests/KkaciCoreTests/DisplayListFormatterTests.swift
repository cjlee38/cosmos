import CoreGraphics
@testable import KkaciCore
import XCTest

final class DisplayListFormatterTests: XCTestCase {
    func testFormatsDisplaySlotNameAndRole() {
        let monitorSlots = [
            MonitorSlotSnapshot(
                slot: 1,
                display: DisplaySnapshot(
                    id: 10,
                    name: "LG ULTRAFINE",
                    frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                    role: .main
                )
            ),
            MonitorSlotSnapshot(
                slot: 2,
                display: DisplaySnapshot(
                    id: 20,
                    name: "Built-in Retina Display",
                    frame: CGRect(x: -1512, y: 300, width: 1512, height: 982),
                    role: .extended
                )
            )
        ]

        XCTAssertEqual(DisplayListFormatter.lines(for: monitorSlots), [
            "1 (LG ULTRAFINE)  Main",
            "2 (Built-in Retina Display)  Extended"
        ])
    }
}
