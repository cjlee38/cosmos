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

    func testWorkspaceNameIsAnOptionalDisplayAlias() {
        let named = WorkspaceConfig(id: "A", name: "  Develop  ")
        let unnamed = WorkspaceConfig(id: "B", name: "   ")

        XCTAssertEqual(named.name, "Develop")
        XCTAssertEqual(named.displayName, "Develop")
        XCTAssertNil(unnamed.name)
        XCTAssertEqual(unnamed.displayName, "B")
    }

    func testNamingWorkspacePreservesIdentityDisplayAndShortcuts() throws {
        let shortcuts = WorkspaceShortcutConfig(
            switchWorkspace: "option+d",
            moveWindow: "option+shift+d"
        )
        let config = KkaciConfig(workspaces: [
            WorkspaceConfig(id: "D", display: 2, shortcuts: shortcuts)
        ])

        let named = try XCTUnwrap(config.namingWorkspace("D", name: "Develop"))
        let workspace = try XCTUnwrap(named.workspace(for: "D"))
        XCTAssertEqual(workspace.id, "D")
        XCTAssertEqual(workspace.name, "Develop")
        XCTAssertEqual(workspace.display, 2)
        XCTAssertEqual(workspace.shortcuts, shortcuts)

        let cleared = try XCTUnwrap(named.namingWorkspace("D", name: "  "))
        XCTAssertNil(cleared.workspace(for: "D")?.name)
        XCTAssertEqual(cleared.workspace(for: "D")?.displayName, "D")
    }
}
