import Foundation
@testable import KkaciCore
import XCTest

final class KkaciConfigTests: XCTestCase {
    func testDefaultConfigPathUsesYamlInDotConfigDirectory() {
        XCTAssertEqual(
            FileKkaciConfigStore.default.url,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("kkaci", isDirectory: true)
                .appendingPathComponent("config.yaml")
        )
    }

    func testDefaultConfigProjectsTypedShortcutsToRuntimeBindings() {
        XCTAssertEqual(KkaciConfig.default.workspaceNames, ["1", "2", "3"])
        XCTAssertEqual(KkaciConfig.default.bindings, [
            HotKeyBinding(key: "ctrl+tab", command: "next-workspace"),
            HotKeyBinding(key: "ctrl+shift+tab", command: "previous-workspace"),
            HotKeyBinding(key: "option+tab", command: "next-window"),
            HotKeyBinding(key: "option+shift+tab", command: "previous-window"),
            HotKeyBinding(key: "option+1", command: "workspace", workspace: "1"),
            HotKeyBinding(key: "option+shift+1", command: "move-window-to-workspace", workspace: "1"),
            HotKeyBinding(key: "option+2", command: "workspace", workspace: "2"),
            HotKeyBinding(key: "option+shift+2", command: "move-window-to-workspace", workspace: "2"),
            HotKeyBinding(key: "option+3", command: "workspace", workspace: "3"),
            HotKeyBinding(key: "option+shift+3", command: "move-window-to-workspace", workspace: "3")
        ])
    }

    func testWorkspaceShortcutBindingsUseTheNonModifierKey() {
        let shortcuts = WorkspaceShortcutBindings([
            HotKeyBinding(key: "option+1", command: "workspace", workspace: "1"),
            HotKeyBinding(key: "option+b", command: "workspace", workspace: "build"),
            HotKeyBinding(key: "option+shift+c", command: "move-window-to-workspace", workspace: "build")
        ])

        XCTAssertEqual(shortcuts.key(for: "1"), "1")
        XCTAssertEqual(shortcuts.key(for: "build"), "b")
        XCTAssertEqual(shortcuts.workspace(for: "B"), "build")
        XCTAssertNil(shortcuts.workspace(for: "c"))
    }

    func testConfigNormalizesWorkspaceNamesAndDisplaySlots() {
        let config = KkaciConfig(workspaces: [
            WorkspaceConfig(name: "1"),
            WorkspaceConfig(name: " "),
            WorkspaceConfig(name: "chat", display: 2),
            WorkspaceConfig(name: "1", display: 3),
            WorkspaceConfig(name: "bad", display: 0)
        ])

        XCTAssertEqual(config.workspaceNames, ["1", "chat", "bad"])
        XCTAssertEqual(config.monitorSlot(for: "chat"), 2)
        XCTAssertEqual(config.monitorSlot(for: "bad"), 1)
        XCTAssertEqual(config.monitorSlot(for: "missing"), 1)
    }

    func testAssigningWorkspaceMonitorPreservesWorkspaceShortcuts() {
        let workspaceShortcuts = WorkspaceShortcutConfig(
            switchWorkspace: "option+2",
            moveWindow: "option+shift+2"
        )
        let config = KkaciConfig(workspaces: [
            WorkspaceConfig(name: "1"),
            WorkspaceConfig(name: "2", shortcuts: workspaceShortcuts)
        ])

        let updated = config.assigningWorkspace("2", toMonitorSlot: 3)

        XCTAssertEqual(updated.monitorSlot(for: "2"), 3)
        XCTAssertEqual(updated.workspaces[1].shortcuts, workspaceShortcuts)
    }

    func testFileConfigStoreRoundTripsYamlConfig() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = KkaciConfig(
            workspaces: [
                WorkspaceConfig(name: "1"),
                WorkspaceConfig(
                    name: "dev",
                    display: 2,
                    shortcuts: WorkspaceShortcutConfig(switchWorkspace: "option+d")
                )
            ],
            shortcuts: ShortcutConfig(
                workspaceSwitcher: SwitcherShortcutConfig(next: "ctrl+tab")
            )
        )
        let store = FileKkaciConfigStore(url: url)

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testFileConfigStoreLoadsWorkspaceCentricYaml() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let yaml = """
        version: 1
        shortcuts:
          workspace_switcher:
            next: ctrl+tab
            previous: ctrl+shift+tab
          window_switcher:
            next: option+tab
            previous: option+shift+tab
        workspaces:
          - name: "1"
            display: 1
            shortcuts:
              switch: option+1
              move_window: option+shift+1
          - name: dev
            display: 2
            shortcuts:
              switch: option+d
              move_window: option+shift+d
        """
        try yaml.write(to: url, atomically: true, encoding: .utf8)

        let config = try FileKkaciConfigStore(url: url).load()

        XCTAssertEqual(config.workspaceNames, ["1", "dev"])
        XCTAssertEqual(config.monitorSlot(for: "dev"), 2)
        XCTAssertEqual(config.shortcuts.workspaceSwitcher.next, "ctrl+tab")
        XCTAssertEqual(config.workspaces[1].shortcuts.moveWindow, "option+shift+d")
    }

    func testMissingConfigCreatesAndReturnsDefaultYaml() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileKkaciConfigStore(url: url)

        let config = try store.load()
        let yaml = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(config, .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(yaml.contains("version: 1"))
        XCTAssertTrue(yaml.contains("workspace_switcher:"))
        XCTAssertTrue(yaml.contains("workspaces:"))
        XCTAssertFalse(yaml.contains("bindings:"))
        XCTAssertEqual(try store.load(), .default)
    }

    func testSaveRewritesCustomCommentsWithTheStandardHeader() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# My custom comment\n".write(to: url, atomically: true, encoding: .utf8)

        try FileKkaciConfigStore(url: url).save(.default)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("""
        # Kkaci configuration file
        #
        # - Warning
        """))
        XCTAssertTrue(content.contains("# - Shortcut modifiers"))
        XCTAssertTrue(content.contains("# - Display slots"))
        XCTAssertFalse(content.contains("# My custom comment"))
    }

    func testInvalidExistingConfigIsNotOverwritten() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalidYaml = "version: nope\nworkspaces: ["
        try invalidYaml.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try FileKkaciConfigStore(url: url).load())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), invalidYaml)
    }

    func testUnsupportedConfigVersionIsRejected() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "version: 2\nworkspaces:\n  - name: 1\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try FileKkaciConfigStore(url: url).load())
    }

    private func temporaryConfigLocation() -> (directory: URL, config: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kkaci-config-tests-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("config.yaml"))
    }
}
