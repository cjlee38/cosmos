import Foundation
import TOMLKit

public final class FileKkaciConfigStore: KkaciConfigStore {
    public static let `default` = FileKkaciConfigStore(
        url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("kkaci", isDirectory: true)
            .appendingPathComponent("config.toml")
    )

    public let url: URL
    private let fileManager: FileManager

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    public func load() throws -> KkaciConfig {
        guard fileManager.fileExists(atPath: url.path) else {
            let config = KkaciConfig.default
            try save(config)
            return config
        }

        let toml = try String(contentsOf: url, encoding: .utf8)
        let table = try TOMLTable(string: toml)
        return try TOMLDecoder().decode(KkaciConfig.self, from: table)
    }

    public func save(_ config: KkaciConfig) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let table: TOMLTable = try TOMLEncoder().encode(config)
        let toml = table.convert(to: .toml)
        try toml.write(to: url, atomically: true, encoding: .utf8)
    }
}
