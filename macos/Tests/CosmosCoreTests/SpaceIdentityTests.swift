@testable import CosmosCore
import XCTest

final class SpaceIdentityTests: XCTestCase {
    func testSpaceIDsUseZeroThroughNineThenLetters() {
        XCTAssertEqual(
            SpaceID.allCases.map(\.rawValue),
            (0 ... 9).map(String.init) + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        )
    }

    func testSpaceZeroUsesZeroAsItsDefaultShortcutKey() throws {
        let config = try XCTUnwrap(CosmosConfig.default.addingSpace("0"))
        let space = try XCTUnwrap(config.spaces.first { $0.id == "0" })

        XCTAssertEqual(space.shortcuts, SpaceShortcutConfig(
            switchSpace: "option+0",
            moveWindow: "option+shift+0"
        ))
    }
}
