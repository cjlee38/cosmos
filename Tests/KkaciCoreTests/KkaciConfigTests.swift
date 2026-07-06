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

    func testAssigningWorkspaceMonitorPreservesHotKeyBindings() {
        let binding = HotKeyBinding(key: "option+1", command: "workspace", workspace: "1")
        let config = KkaciConfig(
            workspaces: WorkspaceConfig(names: ["1", "2"]),
            bindings: [binding]
        )

        let updated = config.assigningWorkspace("2", toMonitorSlot: 3)

        XCTAssertEqual(updated.workspaces.monitorSlot(for: "2"), 3)
        XCTAssertEqual(updated.bindings, [binding])
    }

    func testWorkspaceConfigNormalizesMonitorSlots() {
        let config = WorkspaceConfig(
            names: ["1", "chat"],
            monitorSlotsByName: ["1": 1, "chat": 2, "ghost": 3, "bad": 0]
        )

        XCTAssertEqual(config.monitorSlotsByName, ["1": 1, "chat": 2])
        XCTAssertEqual(config.monitorSlot(for: "chat"), 2)
        XCTAssertEqual(config.monitorSlot(for: "missing"), 1)
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
                HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")
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
            HotKeyBinding(key: "option+d", command: "workspace", workspace: "dev")
        ])
    }

    func testFileConfigStoreLoadsWorkspaceMonitorSlots() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-config-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.toml")
        let toml = """
        [workspaces]
        names = ["1", "chat"]

        [workspaces.monitors]
        chat = 2

        [[bindings]]
        key = "option+1"
        command = "workspace"
        workspace = "1"
        """
        try toml.write(to: url, atomically: true, encoding: .utf8)

        let config = try FileKkaciConfigStore(url: url).load()

        XCTAssertEqual(config.workspaces.names, ["1", "chat"])
        XCTAssertEqual(config.workspaces.monitorSlot(for: "1"), 1)
        XCTAssertEqual(config.workspaces.monitorSlot(for: "chat"), 2)
    }
}
