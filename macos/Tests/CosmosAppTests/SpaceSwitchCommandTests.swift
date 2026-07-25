@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceSwitchCommandTests: XCTestCase {
    func testSwitchingToVisibleSpaceOnAnotherDisplayMovesCursorToDisplayCenter() throws {
        let controller = try makeController(
            spaces: [
                SpaceConfig(id: "1", display: 1),
                SpaceConfig(id: "A", display: 2)
            ]
        )
        var cursorPositions: [CGPoint] = []
        let command = SpaceSwitchCommand(
            controller: controller,
            warpCursor: {
                cursorPositions.append($0)
                return .success
            }
        )

        XCTAssertTrue(try command.execute(to: "A"))

        XCTAssertEqual(controller.currentSpace, "A")
        XCTAssertEqual(cursorPositions, [CGPoint(x: 1600, y: 400)])
    }

    func testSwitchingSpaceOnSameDisplayDoesNotMoveCursor() throws {
        let controller = try makeController(
            spaces: [
                SpaceConfig(id: "1", display: 1),
                SpaceConfig(id: "2", display: 1)
            ]
        )
        var cursorPositions: [CGPoint] = []
        let command = SpaceSwitchCommand(
            controller: controller,
            warpCursor: {
                cursorPositions.append($0)
                return .success
            }
        )

        XCTAssertTrue(try command.execute(to: "2"))

        XCTAssertEqual(controller.currentSpace, "2")
        XCTAssertTrue(cursorPositions.isEmpty)
    }

    func testMissingSpaceDoesNotMoveCursor() throws {
        let controller = try makeController(spaces: [SpaceConfig(id: "1", display: 1)])
        var cursorPositions: [CGPoint] = []
        let command = SpaceSwitchCommand(
            controller: controller,
            warpCursor: {
                cursorPositions.append($0)
                return .success
            }
        )

        XCTAssertFalse(try command.execute(to: "A"))

        XCTAssertEqual(controller.currentSpace, "1")
        XCTAssertTrue(cursorPositions.isEmpty)
    }

    private func makeController(spaces: [SpaceConfig]) throws -> SpaceController {
        let displays = [
            DisplaySnapshot(
                id: 1,
                frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
                role: .main
            ),
            DisplaySnapshot(
                id: 2,
                frame: CGRect(x: 1000, y: 0, width: 1200, height: 800),
                role: .extended
            )
        ]
        let controller = SpaceController(
            windowSystem: SwitcherTestWindowSystem(windows: []),
            displayProvider: SwitcherTestDisplayProvider(snapshots: displays),
            configStore: ConfigStoreSpy(loadedConfig: CosmosConfig(spaces: spaces))
        )
        try controller.bootstrapWindowState()
        return controller
    }
}
