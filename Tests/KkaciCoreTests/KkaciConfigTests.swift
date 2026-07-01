import Foundation
@testable import KkaciCore
import XCTest

final class KkaciConfigTests: XCTestCase {
    func testWorkspaceConfigNormalizesNames() {
        let config = WorkspaceConfig(names: ["1", " ", "2", "1", "dev"])

        XCTAssertEqual(config.names, ["1", "2", "dev"])
    }

    func testAddingWorkspacePreservesHotKeyBindings() {
        let binding = HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")
        let config = KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2"]),
            bindings: [binding]
        )

        let updated = config.addingWorkspace(named: "dev")

        XCTAssertEqual(updated.workspaces.names, ["1", "2", "dev"])
        XCTAssertEqual(updated.bindings, [binding])
    }

    func testFileConfigStorePersistsTomlConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-config-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FileKkaciConfigStore(
            url: directory.appendingPathComponent("config.toml")
        )
        let config = KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2", "dev"]),
            bindings: [
                HotKeyBinding(key: "ctrl+tab", command: "next-workspace"),
                HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev"),
            ]
        )

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
    }

    func testFileConfigStoreLoadsUserWrittenTomlConfig() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-config-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.toml")
        let toml = """
        [workspaces]
        names = ["1", "2", "dev"]

        [[bindings]]
        key = "ctrl+tab"
        command = "next-workspace"

        [[bindings]]
        key = "option+d"
        command = "workspace"
        workspace = "dev"
        """
        try toml.write(to: url, atomically: true, encoding: .utf8)

        let config = try FileKkaciConfigStore(url: url).load()

        XCTAssertEqual(config.workspaces.names, ["1", "2", "dev"])
        XCTAssertEqual(config.bindings, [
            HotKeyBinding(key: "ctrl+tab", command: "next-workspace"),
            HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev"),
        ])
    }
}
