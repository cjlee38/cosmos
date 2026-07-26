import CoreGraphics
@testable import CosmosCore
import XCTest

final class SpaceControllerWindowOperationsTests: SpaceControllerTestCase {
    func testRestoreHiddenWindowUsesCurrentDisplayWhenOriginalFrameIsOffscreen() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One", frame: .frame(x: 1400, y: 120, width: 300, height: 240))
        ])
        let controller = makeController(windowSystem, displayProvider: FakeDisplayProvider(point: hidePoint))

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "2", controller: controller, windowSystem: windowSystem)

        _ = try controller.switchSpace(to: "2")

        XCTAssertEqual(
            windowSystem.frames[100],
            .frame(x: 700, y: 120, width: 300, height: 240)
        )
        XCTAssertEqual(controller.spaceFrame(for: 100), windowSystem.frames[100])
    }

    func testFocusWindowFocusesVisibleSpaceWindow() throws {
        let windowSystem = FakeWindowSystem(windows: [
            .window(id: 100, title: "One"),
            .window(id: 200, title: "Two")
        ])
        let controller = makeController(windowSystem)

        _ = try controller.handleWindowSetChanged()
        try moveWindow(100, to: "1", controller: controller, windowSystem: windowSystem)
        try moveWindow(200, to: "1", controller: controller, windowSystem: windowSystem)

        try controller.focusWindow(200)

        XCTAssertEqual(windowSystem.focusedIDs, [200])
    }
}
