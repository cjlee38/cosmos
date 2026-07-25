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
            AppProfile.debug.hiddenWindowRecordsURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/cosmos-dev/hidden-window-records.json"
        )
        XCTAssertEqual(
            AppProfile.release.hiddenWindowRecordsURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/cosmos/hidden-window-records.json"
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
