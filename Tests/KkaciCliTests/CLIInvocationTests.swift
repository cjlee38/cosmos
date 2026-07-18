@testable import KkaciCli
import XCTest

final class CLIInvocationTests: XCTestCase {
    func testNoArgumentsStartsREPL() {
        XCTAssertEqual(CLIInvocation(arguments: []), .repl)
    }

    func testDisplaysArgumentSelectsOneShotDisplayListing() {
        XCTAssertEqual(CLIInvocation(arguments: ["displays"]), .displays)
    }

    func testAnyOtherArgumentIsInvalid() {
        XCTAssertEqual(CLIInvocation(arguments: ["unknown"]), .invalid)
        XCTAssertEqual(CLIInvocation(arguments: ["displays", "extra"]), .invalid)
    }
}
