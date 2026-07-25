import CoreGraphics
@testable import CosmosCore
import XCTest

final class RestorableFrameResolverTests: XCTestCase {
    func testKeepsFrameWhenCenterIsOnCurrentDisplay() throws {
        let resolver = RestorableFrameResolver(displayProvider: FakeDisplayProvider())
        let frame = WindowFrame.frame(x: 100, y: 120, width: 300, height: 240)

        XCTAssertEqual(try resolver.frameForRestore(frame), frame)
    }

    func testClampsFrameWhenCenterIsOutsideCurrentDisplays() throws {
        let resolver = RestorableFrameResolver(displayProvider: FakeDisplayProvider())
        let frame = WindowFrame.frame(x: 1400, y: 120, width: 300, height: 240)

        XCTAssertEqual(
            try resolver.frameForRestore(frame),
            WindowFrame.frame(x: 700, y: 120, width: 300, height: 240)
        )
    }

    func testClampsCornerHiddenFrameIntoVisibleArea() throws {
        let resolver = RestorableFrameResolver(displayProvider: FakeDisplayProvider(
            snapshots: [
                DisplaySnapshot(
                    id: 1,
                    frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
                    visibleFrame: CGRect(x: 0, y: 40, width: 1000, height: 900),
                    role: .main
                )
            ]
        ))
        let frame = WindowFrame.frame(x: 999, y: 999, width: 1000, height: 1000)

        XCTAssertEqual(
            try resolver.frameForRestore(frame),
            WindowFrame.frame(x: 0, y: 40, width: 1000, height: 1000)
        )
    }
}
