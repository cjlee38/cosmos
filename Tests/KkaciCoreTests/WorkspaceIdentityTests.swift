@testable import KkaciCore
import XCTest

final class WorkspaceIdentityTests: XCTestCase {
    func testWorkspaceIDsUseZeroThroughNineThenLetters() {
        XCTAssertEqual(
            WorkspaceID.allCases.map(\.rawValue),
            (0 ... 9).map(String.init) + "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        )
    }

    func testWorkspaceZeroUsesZeroAsItsDefaultShortcutKey() throws {
        let config = try XCTUnwrap(KkaciConfig.default.addingWorkspace("0"))
        let workspace = try XCTUnwrap(config.workspaces.first { $0.id == "0" })

        XCTAssertEqual(workspace.shortcuts, WorkspaceShortcutConfig(
            switchWorkspace: "option+0",
            moveWindow: "option+shift+0"
        ))
    }
}
