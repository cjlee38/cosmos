@testable import KkaciCli
import XCTest

final class REPLCommandTests: XCTestCase {
    func testCommandAliasesResolveToTheirCanonicalCommands() {
        XCTAssertEqual(REPLCommand(parts: ["help"]), .help)
        XCTAssertEqual(REPLCommand(parts: ["?"]), .help)
        XCTAssertEqual(REPLCommand(parts: ["list"]), .list)
        XCTAssertEqual(REPLCommand(parts: ["ls"]), .list)
        XCTAssertEqual(REPLCommand(parts: ["permission"]), .permission)
        XCTAssertEqual(REPLCommand(parts: ["displays"]), .displays)
        XCTAssertEqual(REPLCommand(parts: ["focused"]), .focused)
        XCTAssertEqual(REPLCommand(parts: ["switch", "2"]), .switchWorkspace("2"))
        XCTAssertEqual(REPLCommand(parts: ["ws", "2"]), .switchWorkspace("2"))
        XCTAssertEqual(REPLCommand(parts: ["move", "3"]), .moveWindow("3"))
        XCTAssertEqual(REPLCommand(parts: ["unhide-all"]), .unhideAll)
        XCTAssertEqual(REPLCommand(parts: ["workspaces"]), .workspaces)
        XCTAssertEqual(REPLCommand(parts: ["quit"]), .quit)
        XCTAssertEqual(REPLCommand(parts: ["exit"]), .quit)
    }

    func testCommandsWithInvalidArgumentsPreserveTheirUsageMessage() {
        XCTAssertEqual(
            REPLCommand(parts: ["switch"]),
            .invalidUsage("usage: switch <workspace>")
        )
        XCTAssertEqual(
            REPLCommand(parts: ["move", "2", "extra"]),
            .invalidUsage("usage: move <workspace>")
        )
        XCTAssertEqual(
            REPLCommand(parts: ["unhide-all", "extra"]),
            .invalidUsage("usage: unhide-all")
        )
    }

    func testUnknownCommandPreservesRawInput() {
        guard case let .unknown(raw) = REPLCommand(parts: ["missing-command"]) else {
            return XCTFail("Expected an unknown command")
        }

        XCTAssertEqual(raw, "missing-command")
    }
}
