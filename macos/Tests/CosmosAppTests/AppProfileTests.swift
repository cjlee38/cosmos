@testable import CosmosApp
import XCTest

final class AppProfileTests: XCTestCase {
    func testDebugAndReleaseProfilesUseSeparateDataDirectories() {
        let homeDirectory = URL(fileURLWithPath: "/Users/test")
        let applicationSupportDirectory = URL(fileURLWithPath: "/Users/test/Library/Application Support")

        XCTAssertEqual(
            AppProfile.debug.configURL(homeDirectory: homeDirectory).path,
            "/Users/test/.config/cosmos-dev/config.yaml"
        )
        XCTAssertEqual(
            AppProfile.release.configURL(homeDirectory: homeDirectory).path,
            "/Users/test/.config/cosmos/config.yaml"
        )
        XCTAssertEqual(
            AppProfile.debug.sessionStateURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/cosmos-dev/session-state.json"
        )
        XCTAssertEqual(
            AppProfile.release.sessionStateURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/cosmos/session-state.json"
        )
    }

    func testCurrentProfileUsesDebugDataDuringDebugBuilds() {
        #if DEBUG
            XCTAssertEqual(AppProfile.current, .debug)
        #else
            XCTAssertEqual(AppProfile.current, .release)
        #endif
    }
}
