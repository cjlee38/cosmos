@testable import KkaciApp
import XCTest

final class ConfigErrorMessageTests: XCTestCase {
    func testShowsUnderlyingParserMessageWithoutDecodingErrorWrapper() {
        let error = DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: [],
            debugDescription: "The given data was not valid YAML.",
            underlyingError: ParserMessageError()
        ))

        XCTAssertEqual(ConfigErrorMessage.describe(error), "line 28: expected ':'")
    }
}

private struct ParserMessageError: Error, CustomStringConvertible {
    var description: String {
        "line 28: expected ':'"
    }
}
