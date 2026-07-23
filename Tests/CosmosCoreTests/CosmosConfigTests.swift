import Foundation
@testable import CosmosCore
import XCTest

final class CosmosConfigTests: XCTestCase {
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
            FileCosmosConfigStore.default.url,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("cosmos", isDirectory: true)
                .appendingPathComponent("config.yaml")
        )
    }

    func testDefaultConfigProjectsConfiguredShortcutsWithTypedTargets() {
        XCTAssertEqual(CosmosConfig.default.spaces.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(CosmosConfig.default.configuredShortcuts, [
            ConfiguredShortcut(key: "option+shift+tab", target: .spaceSwitcher),
            ConfiguredShortcut(key: "option+tab", target: .windowSwitcher),
            ConfiguredShortcut(key: "option+command+c", target: .centerWindow),
            ConfiguredShortcut(key: "option+1", target: .switchSpace("1")),
            ConfiguredShortcut(key: "option+shift+1", target: .moveWindow("1")),
            ConfiguredShortcut(key: "option+2", target: .switchSpace("2")),
            ConfiguredShortcut(key: "option+shift+2", target: .moveWindow("2")),
            ConfiguredShortcut(key: "option+3", target: .switchSpace("3")),
            ConfiguredShortcut(key: "option+shift+3", target: .moveWindow("3"))
        ])
    }

    func testConfigOrdersSpaceIDsAndNormalizesDisplaySlots() {
        let config = CosmosConfig(spaces: [
            SpaceConfig(id: "B", display: 0),
            SpaceConfig(id: "1"),
            SpaceConfig(id: "0"),
            SpaceConfig(id: "A", display: 2)
        ])

        XCTAssertEqual(config.spaces.map(\.id), ["0", "1", "A", "B"])
        XCTAssertEqual(config.spaces.map(\.display), [1, 1, 2, 1])
    }

    func testAddingAndRemovingSpaceUsesCanonicalOrderAndDefaultShortcuts() throws {
        let added = try XCTUnwrap(CosmosConfig.default.addingSpace("A", display: 2))

        XCTAssertEqual(added.spaces.map(\.id), ["1", "2", "3", "A"])
        XCTAssertEqual(added.spaces.last?.display, 2)
        XCTAssertEqual(added.spaces.last?.shortcuts, SpaceShortcutConfig(
            switchSpace: "option+a",
            moveWindow: "option+shift+a"
        ))
        XCTAssertNil(added.addingSpace("A"))

        let removed = try XCTUnwrap(added.removingSpace("2"))
        XCTAssertEqual(removed.spaces.map(\.id), ["1", "3", "A"])
    }

    func testAddingMultipleSpacesUsesOneCanonicalConfig() throws {
        let config = try XCTUnwrap(CosmosConfig.default.addingSpaces(["B", "0", "A", "B"]))

        XCTAssertEqual(config.spaces.map(\.id), ["0", "1", "2", "3", "A", "B"])
    }

    func testRemovingTheLastSpaceIsRejected() {
        let config = CosmosConfig(spaces: [SpaceConfig(id: "1")])

        XCTAssertNil(config.removingSpace("1"))
    }

    func testAssigningSpaceMonitorPreservesSpaceShortcuts() throws {
        let spaceShortcuts = SpaceShortcutConfig(
            switchSpace: "option+2",
            moveWindow: "option+shift+2"
        )
        let config = CosmosConfig(spaces: [
            SpaceConfig(id: "1"),
            SpaceConfig(id: "2", shortcuts: spaceShortcuts)
        ])

        let updated = try config.assigningSpace(XCTUnwrap(SpaceID(rawValue: "2")), toMonitorSlot: 3)

        XCTAssertEqual(updated.spaces[1].display, 3)
        XCTAssertEqual(updated.spaces[1].shortcuts, spaceShortcuts)
    }

    func testUpdatingSwitcherShortcutsChangesOnlyTheSelectedTarget() throws {
        let config = CosmosConfig.default

        let space = try XCTUnwrap(config.updatingShortcut(
            "command+tab",
            for: .spaceSwitcher
        ))
        XCTAssertEqual(space.switcher.shortcuts.space, "command+tab")
        XCTAssertEqual(space.switcher.shortcuts.window, config.switcher.shortcuts.window)

        let window = try XCTUnwrap(config.updatingShortcut(
            "command+shift+tab",
            for: .windowSwitcher
        ))
        XCTAssertEqual(window.switcher.shortcuts.window, "command+shift+tab")
        XCTAssertEqual(window.switcher.shortcuts.space, config.switcher.shortcuts.space)
    }

    func testUpdatingCenterWindowShortcutPreservesOtherConfig() throws {
        let config = CosmosConfig.default

        let updated = try XCTUnwrap(config.updatingShortcut("control+option+c", for: .centerWindow))

        XCTAssertEqual(updated.window.shortcuts.center, "control+option+c")
        XCTAssertEqual(updated.switcher, config.switcher)
        XCTAssertEqual(updated.spaces, config.spaces)
    }

    func testUpdatingSpaceShortcutsPreservesTheOtherSpaceFields() throws {
        let config = CosmosConfig.default

        let switched = try XCTUnwrap(config.updatingShortcut("control+a", for: .switchSpace("2")))
        XCTAssertEqual(switched.spaces[1].shortcuts.switchSpace, "control+a")
        XCTAssertEqual(switched.spaces[1].shortcuts.moveWindow, "option+shift+2")

        let moved = try XCTUnwrap(config.updatingShortcut("command+a", for: .moveWindow("2")))
        XCTAssertEqual(moved.spaces[1].shortcuts.switchSpace, "option+2")
        XCTAssertEqual(moved.spaces[1].shortcuts.moveWindow, "command+a")
        XCTAssertEqual(moved.spaces[1].display, config.spaces[1].display)
    }

    func testUpdatingShortcutClearsBlankValuesAndRejectsUnknownSpace() throws {
        let cleared = try XCTUnwrap(CosmosConfig.default.updatingShortcut(
            "  \n ",
            for: .spaceSwitcher
        ))

        XCTAssertNil(cleared.switcher.shortcuts.space)
        XCTAssertNil(CosmosConfig.default.updatingShortcut("option+a", for: .switchSpace("A")))
    }

    func testFileConfigStoreRoundTripsYamlConfig() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = CosmosConfig(
            spaces: [
                SpaceConfig(id: "1"),
                SpaceConfig(
                    id: "D",
                    display: 2,
                    shortcuts: SpaceShortcutConfig(switchSpace: "option+d")
                )
            ],
            switcher: SwitcherConfig(
                shortcuts: SwitcherShortcutConfig(space: "option+shift+tab")
            )
        )
        let store = FileCosmosConfigStore(url: url)

        try store.save(config)

        XCTAssertEqual(try store.load(), config)
    }

    func testFileConfigStoreLoadsSpaceCentricYaml() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let yaml = """
        version: 1
        switcher:
          shortcuts:
            space: option+shift+tab
            window: option+tab
        spaces:
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

        let config = try FileCosmosConfigStore(url: url).load()

        XCTAssertEqual(config.spaces.map(\.id), ["1", "D"])
        XCTAssertEqual(config.spaces[1].display, 2)
        XCTAssertEqual(config.switcher.shortcuts.space, "option+shift+tab")
        XCTAssertEqual(config.spaces[1].shortcuts.moveWindow, "option+shift+d")
    }

    func testInvalidSpaceIDsAreRejected() throws {
        for invalidID in [".", "10", "11", "AA"] {
            let (directory, url) = temporaryConfigLocation()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "version: 1\nspaces:\n  - id: '\(invalidID)'\n".write(
                to: url,
                atomically: true,
                encoding: .utf8
            )

            XCTAssertThrowsError(try FileCosmosConfigStore(url: url).load())
        }
    }

    func testDuplicateSpaceIDsAreRejectedAfterNormalization() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "version: 1\nspaces:\n  - id: A\n  - id: a\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try FileCosmosConfigStore(url: url).load())
    }

    func testMissingConfigCreatesAndReturnsDefaultYaml() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileCosmosConfigStore(url: url)

        let config = try store.load()
        let yaml = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(config, .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(yaml.contains("version: 1"))
        XCTAssertTrue(yaml.contains("switcher:"))
        XCTAssertTrue(yaml.contains("space: option+shift+tab"))
        XCTAssertTrue(yaml.contains("center: option+command+c"))
        XCTAssertTrue(yaml.contains("spaces:"))
        XCTAssertFalse(yaml.contains("bindings:"))
        XCTAssertEqual(try store.load(), .default)
    }

    func testSaveRewritesCustomCommentsWithTheStandardHeader() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "# My custom comment\n".write(to: url, atomically: true, encoding: .utf8)

        try FileCosmosConfigStore(url: url).save(.default)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("""
        # Cosmos configuration file
        #
        # - Warning
        """))
        XCTAssertTrue(content.contains("# - Shortcut modifiers"))
        XCTAssertTrue(content.contains("# - Space IDs"))
        XCTAssertTrue(content.contains("# - Display slots"))
        XCTAssertFalse(content.contains("# My custom comment"))
    }

    func testInvalidExistingConfigIsNotOverwritten() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let invalidYaml = "version: nope\nspaces: ["
        try invalidYaml.write(to: url, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try FileCosmosConfigStore(url: url).load())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), invalidYaml)
    }

    func testUnsupportedConfigVersionIsRejected() throws {
        let (directory, url) = temporaryConfigLocation()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "version: 2\nspaces:\n  - id: 1\n".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(try FileCosmosConfigStore(url: url).load())
    }

    private func temporaryConfigLocation() -> (directory: URL, config: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cosmos-config-tests-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("config.yaml"))
    }
}
