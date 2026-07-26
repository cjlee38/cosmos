@testable import CosmosCore
import Foundation
import XCTest

final class ConfigStrictDecodingTests: XCTestCase {
    func testOptionalConfigSectionsMayBeOmitted() throws {
        let yaml = """
        version: 1
        spaces:
          - id: 1
            display: 1
            shortcuts: {}
        """

        let config = try load(yaml)

        XCTAssertEqual(config.switcher, .empty)
        XCTAssertEqual(config.window, .default)
    }

    func testUnknownConfigKeysAreRejectedAtEveryObjectLevel() throws {
        for yaml in invalidYamls {
            XCTAssertThrowsError(try load(yaml)) { error in
                guard case let DecodingError.dataCorrupted(context) = error else {
                    return XCTFail("Expected dataCorrupted, got \(error)")
                }
                XCTAssertEqual(context.debugDescription, "Unknown config key: unknown")
            }
        }
    }

    private var invalidYamls: [String] {
        [
            """
            version: 1
            unknown: true
            spaces: \(validSpaces)
            """,
            """
            version: 1
            switcher:
              shortcuts: {}
              unknown: true
            spaces: \(validSpaces)
            """,
            """
            version: 1
            switcher:
              shortcuts:
                unknown: true
            spaces: \(validSpaces)
            """,
            """
            version: 1
            window:
              shortcuts: {}
              unknown: true
            spaces: \(validSpaces)
            """,
            """
            version: 1
            window:
              shortcuts:
                unknown: true
            spaces: \(validSpaces)
            """,
            """
            version: 1
            spaces:
              - id: 1
                display: 1
                shortcuts: {}
                unknown: true
            """,
            """
            version: 1
            spaces:
              - id: 1
                display: 1
                shortcuts:
                  unknown: true
            """
        ]
    }

    private var validSpaces: String {
        """

          - id: 1
            display: 1
            shortcuts: {}
        """
    }

    private func load(_ yaml: String) throws -> CosmosConfig {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-config-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.yaml")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        return try FileCosmosConfigStore(url: url).load()
    }
}
