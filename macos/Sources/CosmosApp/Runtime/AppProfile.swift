import Foundation

struct AppProfile: Equatable {
    static let debug = AppProfile(dataDirectoryName: "cosmos-dev")
    static let release = AppProfile(dataDirectoryName: "cosmos")

    static var current: AppProfile {
        #if DEBUG
            .debug
        #else
            .release
        #endif
    }

    let dataDirectoryName: String

    var configURL: URL {
        configURL(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    var hiddenWindowRecordsURL: URL {
        hiddenWindowRecordsURL(
            applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
        )
    }

    func configURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .appendingPathComponent("config.yaml")
    }

    func hiddenWindowRecordsURL(applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
            .appendingPathComponent("hidden-window-records.json")
    }
}
