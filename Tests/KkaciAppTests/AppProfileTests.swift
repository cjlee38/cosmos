@testable import KkaciApp
import XCTest

final class AppProfileTests: XCTestCase {
    func testDebugAndReleaseProfilesUseSeparateDataDirectories() {
        let homeDirectory = URL(fileURLWithPath: "/Users/test")
        let applicationSupportDirectory = URL(fileURLWithPath: "/Users/test/Library/Application Support")

        XCTAssertEqual(
            AppProfile.debug.configURL(homeDirectory: homeDirectory).path,
            "/Users/test/.config/kkaci-dev/config.yaml"
        )
        XCTAssertEqual(
            AppProfile.release.configURL(homeDirectory: homeDirectory).path,
            "/Users/test/.config/kkaci/config.yaml"
        )
        XCTAssertEqual(
            AppProfile.debug.hiddenWindowRecordsURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/kkaci-dev/hidden-window-records.json"
        )
        XCTAssertEqual(
            AppProfile.release.hiddenWindowRecordsURL(
                applicationSupportDirectory: applicationSupportDirectory
            ).path,
            "/Users/test/Library/Application Support/kkaci/hidden-window-records.json"
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
