import Foundation
@testable import KkaciCore
import XCTest

final class KkaciConfigTests: XCTestCase {
    func testShortcutParsesAliasesIntoCanonicalPlatformIndependentParts() throws {
        let shortcut = try Shortcut(parsing: "ctrl+alt+shift+cmd+a")

        XCTAssertEqual(shortcut.modifiers, [.control, .option, .shift, .command])
        XCTAssertEqual(shortcut.key, "a")
    }

    func testShortcutRejectsMissingAndMultipleKeys() {
        XCTAssertThrowsError(try Shortcut(parsing: "option+shift"))
        XCTAssertThrowsError(try Shortcut(parsing: "option+a+b"))
    }

    func testDefaultConfigPathUsesYamlInDotConfigDirectory() {
        XCTAssertEqual(
            FileKkaciConfigStore.default.url,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("kkaci", isDirectory: true)
                .appendingPathComponent("config.yaml")
        )
    }

    func testDefaultConfigProjectsConfiguredShortcutsWithTypedTargets() {
        XCTAssertEqual(KkaciConfig.default.workspaces.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(KkaciConfig.default.configuredShortcuts, [
            ConfiguredShortcut(key: "option+shift+tab", target: .workspaceSwitcher),
            ConfiguredShortcut(key: "option+tab", target: .windowSwitcher),
            ConfiguredShortcut(key: "option+command+c", target: .centerWindow),
            ConfiguredShortcut(key: "option+1", target: .switchWorkspace("1")),
            ConfiguredShortcut(key: "option+shift+1", target: .moveWindow("1")),
            ConfiguredShortcut(key: "option+2", target: .switchWorkspace("2")),
            ConfiguredShortcut(key: "option+shift+2", target: .moveWindow("2")),
            ConfiguredShortcut(key: "option+3", target: .switchWorkspace("3")),
            ConfiguredShortcut(key: "option+shift+3", target: .moveWindow("3"))
        ])
    }

    func testConfigOrdersWorkspaceIDsAndNormalizesDisplaySlots() {
        let config = KkaciConfig(workspaces: [
            WorkspaceConfig(id: "B", display: 0),
            WorkspaceConfig(id: "1"),
            WorkspaceConfig(id: "0"),
            WorkspaceConfig(id: "A", display: 2)
        ])

        XCTAssertEqual(config.workspaces.map(\.id), ["0", "1", "A", "B"])
        XCTAssertEqual(config.workspaces.map(\.display), [1, 1, 2, 1])
    }

    func testAddingAndRemovingWorkspaceUsesCanonicalOrderAndDefaultShortcuts() throws {
        let added = try XCTUnwrap(KkaciConfig.default.addingWorkspace("A", display: 2))

        XCTAssertEqual(added.workspaces.map(\.id), ["1", "2", "3", "A"])
        XCTAssertEqual(added.workspaces.last?.display, 2)
        XCTAssertEqual(added.workspaces.last?.shortcuts, WorkspaceShortcutConfig(
            switchWorkspace: "option+a",
            moveWindow: "option+shift+a"
        ))
        XCTAssertNil(added.addingWorkspace("A"))

        let removed = try XCTUnwrap(added.removingWorkspace("2"))
        XCTAssertEqual(removed.workspaces.map(\.id), ["1", "3", "A"])
    }

    func testAddingMultipleWorkspacesUsesOneCanonicalConfig() throws {
        let config = try XCTUnwrap(KkaciConfig.default.addingWorkspaces(["B", "0", "A", "B"]))

        XCTAssertEqual(config.workspaces.map(\.id), ["0", "1", "2", "3", "A", "B"])
    }

    func testRemovingTheLastWorkspaceIsRejected() {
        let config = KkaciConfig(workspaces: [WorkspaceConfig(id: "1")])

        XCTAssertNil(config.removingWorkspace("1"))
    }

    func testAssigningWorkspaceMonitorPreservesWorkspaceShortcuts() throws {
        let workspaceShortcuts = WorkspaceShortcutConfig(
            switchWorkspace: "option+2",
            moveWindow: "option+shift+2"
        )
        let config = KkaciConfig(workspaces: [
            WorkspaceConfig(id: "1"),
            WorkspaceConfig(id: "2", shortcuts: workspaceShortcuts)
        ])

        let updated = try config.assigningWorkspace(XCTUnwrap(WorkspaceID(rawValue: "2")), toMonitorSlot: 3)

        XCTAssertEqual(updated.workspaces[1].display, 3)
        XCTAssertEqual(updated.workspaces[1].shortcuts, workspaceShortcuts)
    }

    func testUpdatingSwitcherShortcutsChangesOnlyTheSelectedTarget() throws {
        let config = KkaciConfig.default

        let workspace = try XCTUnwrap(config.updatingShortcut(
            "command+tab",
            for: .workspaceSwitcher
        ))
        XCTAssertEqual(workspace.switcher.shortcuts.workspace, "command+tab")
        XCTAssertEqual(workspace.switcher.shortcuts.window, config.switcher.shortcuts.window)

        let window = try XCTUnwrap(config.updatingShortcut(
            "command+shift+tab",
            for: .windowSwitcher
        ))
        XCTAssertEqual(window.switcher.shortcuts.window, "command+shift+tab")
        XCTAssertEqual(window.switcher.shortcuts.workspace, config.switcher.shortcuts.workspace)
    }

    func testUpdatingCenterWindowShortcutPreservesOtherConfig() throws {
        let config = KkaciConfig.default

        let updated = try XCTUnwrap(config.updatingShortcut("control+option+c", for: .centerWindow))

        XCTAssertEqual(updated.window.shortcuts.center, "control+option+c")
        XCTAssertEqual(updated.switcher, config.switcher)
        XCTAssertEqual(updated.workspaces, config.workspaces)
    }

    func testUpdatingWorkspaceShortcutsPreservesTheOtherWorkspaceFields() throws {
        let config = KkaciConfig.default

        let switched = try XCTUnwrap(config.updatingShortcut("control+a", for: .switchWorkspace("2")))
        XCTAssertEqual(switched.workspaces[1].shortcuts.switchWorkspace, "control+a")
        XCTAssertEqual(switched.workspaces[1].shortcuts.moveWindow, "option+shift+2")

        let moved = try XCTUnwrap(config.updatingShortcut("command+a", for: .moveWindow("2")))
        XCTAssertEqual(moved.workspaces[1].shortcuts.switchWorkspace, "option+2")
        XCTAssertEqual(moved.workspaces[1].shortcuts.moveWindow, "command+a")
        XCTAssertEqual(moved.workspaces[1].display, config.workspaces[1].display)
    }

    func testUpdatingShortcutClearsBlankValuesAndRejectsUnknownWorkspace() throws {
        let cleared = try XCTUnwrap(KkaciConfig.default.updatingShortcut(
            "  \n ",
            for: .workspaceSwitcher
        ))

        XCTAssertNil(cleared.switcher.shortcuts.workspace)
        XCTAssertNil(KkaciConfig.default.updatingShortcut("option+a", for: .switchWorkspace("A")))
    }

    func testFileConfigStoreRoundTripsYamlConfig() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = KkaciConfig(
            workspaces: [
                WorkspaceConfig(id: "1"),
                WorkspaceConfig(
                    id: "D",
                    display: 2,
                    shortcuts: WorkspaceShortcutConfig(switchWorkspace: "option+d")
                )
            ],
            switcher: SwitcherConfig(
                shortcuts: SwitcherShortcutConfig(workspace: "option+shift+tab")
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
        switcher:
          shortcuts:
            workspace: option+shift+tab
            window: option+tab
        workspaces:
          - id: 1
            display: 1
            shortcuts:
              switch: option+1
              move_window: option+shift+1
          - id: d
            display: 2
            shortcuts:
              switch: option+d
              move_window: option+shift+d
        """
        try yaml.write(to: url, atomically: true, encoding: .utf8)

        let config = try FileKkaciConfigStore(url: url).load()

        XCTAssertEqual(config.workspaces.map(\.id), ["1", "D"])
        XCTAssertEqual(config.workspaces[1].display, 2)
        XCTAssertEqual(config.switcher.shortcuts.workspace, "option+shift+tab")
        XCTAssertEqual(config.workspaces[1].shortcuts.moveWindow, "option+shift+d")
    }

    func testInvalidWorkspaceIDsAreRejected() throws {
        for invalidID in [".", "10", "11", "AA"] {
            let (directory, url) = temporaryConfigLocation()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "version: 1\nworkspaces:\n  - id: '\(invalidID)'\n".write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            XCTAssertThrowsError(try FileKkaciConfigStore(url: url).load())
        }
    }

    func testDuplicateWorkspaceIDsAreRejectedAfterNormalization() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "version: 1\nworkspaces:\n  - id: A\n  - id: a\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try FileKkaciConfigStore(url: url).load())
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
        XCTAssertTrue(yaml.contains("switcher:"))
        XCTAssertTrue(yaml.contains("workspace: option+shift+tab"))
        XCTAssertTrue(yaml.contains("center: option+command+c"))
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
        XCTAssertTrue(content.contains("# - Workspace IDs"))
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
        try "version: 2\nworkspaces:\n  - id: 1\n".write(
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
