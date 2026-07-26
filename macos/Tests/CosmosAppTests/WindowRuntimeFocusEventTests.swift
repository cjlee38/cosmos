import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class WindowRuntimeFocusEventTests: XCTestCase {
    func testDestroyingFocusedWindowFollowsNewlyFocusedVisibleSpace() throws {
        let mainDisplay = DisplaySnapshot(
            id: 1,
            frame: CGRect(x: 0, y: 0, width: 1000, height: 1000),
            role: .main
        )
        let secondaryDisplay = DisplaySnapshot(
            id: 2,
            frame: CGRect(x: 1000, y: 0, width: 1000, height: 1000),
            role: .extended
        )
        let (controller, windowSystem) = try makeSwitcherTestController(
            windows: [
                makeSwitcherTestWindow(id: 100, title: "Main"),
                makeSwitcherTestWindow(
                    id: 200,
                    title: "Secondary",
                    frame: WindowFrame(
                        origin: CGPoint(x: 1100, y: 100),
                        size: CGSize(width: 200, height: 120)
                    )
                )
            ],
            displays: [mainDisplay, secondaryDisplay]
        )
        try controller.applyConfig(CosmosConfig(
            spaces: [
                SpaceConfig(id: "1", display: 1),
                SpaceConfig(id: "A", display: 2)
            ]
        ))
        try moveSwitcherTestWindow(200, to: "A", controller: controller, windowSystem: windowSystem)
        _ = try controller.switchSpace(to: "A")
        windowSystem.replaceWindows([
            makeSwitcherTestWindow(id: 100, title: "Main")
        ])
        windowSystem.focusedWindowIDValue = 100
        let handler = WindowRuntimeEventHandler(
            controller: controller,
            previewService: makeSwitcherTestPreviewService(controller: controller),
            refreshSwitcherContent: {},
            refreshStatusSurfaces: {},
            scheduleDiscovery: { $0() },
            scheduleApply: { $0() }
        )

        handler.handle(WindowRuntimeEventBatch(events: [
            WindowRuntimeEvent(kind: .windowDestroyed, windowID: nil)
        ]))

        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertEqual(controller.membership(for: 100), "1")
    }
}
