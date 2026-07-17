import AppKit
import CoreGraphics
@testable import KkaciApp
import KkaciCore
import XCTest

final class WorkspaceSettingsTests: XCTestCase {
    func testSnapshotBuildsDisplayAssignmentsAndShortcutRows() {
        let main = DisplaySnapshot(
            id: 1,
            name: "Built-in Retina Display",
            frame: CGRect(x: 1200, y: 0, width: 1600, height: 1000),
            role: .main
        )
        let extended = DisplaySnapshot(
            id: 2,
            name: "Studio Display",
            frame: CGRect(x: 0, y: 200, width: 1200, height: 800),
            role: .extended
        )
        let mirrored = DisplaySnapshot(
            id: 3,
            frame: main.frame,
            role: .mirrored(source: 1)
        )
        let snapshot = WorkspaceSettingsSnapshot(
            config: snapshotConfig(),
            monitorSlots: [
                MonitorSlotSnapshot(slot: 1, display: main),
                MonitorSlotSnapshot(slot: 2, display: extended)
            ],
            displays: [main, extended, mirrored]
        )

        XCTAssertEqual(snapshot.displays[0].workspaceIDs, ["1"])
        XCTAssertEqual(snapshot.displays[0].name, "Built-in Retina Display")
        XCTAssertEqual(snapshot.displays[1].workspaceIDs, ["A"])
        XCTAssertEqual(snapshot.displays[2].mirroredSourceMonitorSlot, 1)
        XCTAssertEqual(snapshot.displays[2].workspaceIDs, [])
        XCTAssertEqual(snapshot.connectedDisplays.compactMap(\.monitorSlot), [1, 2])
        XCTAssertEqual(snapshot.disconnectedMonitorSlots, [3])
        XCTAssertEqual(snapshot.navigation.next, "ctrl+tab")
        XCTAssertEqual(snapshot.navigation.previous, "ctrl+shift+tab")
        XCTAssertEqual(snapshot.workspaces[0].switchShortcut, "option+1")
        XCTAssertEqual(snapshot.workspaces[0].moveShortcut, "option+shift+1")
        XCTAssertNil(snapshot.workspaces[1].switchShortcut)
        XCTAssertFalse(snapshot.availableWorkspaceIDs.contains("1"))
        XCTAssertFalse(snapshot.availableWorkspaceIDs.contains("A"))
        XCTAssertTrue(snapshot.availableWorkspaceIDs.contains("B"))
    }

    func testShortcutFormatterUsesMacModifierSymbols() {
        XCTAssertEqual(ShortcutDisplayFormatter.format("ctrl+shift+tab"), "⌃ ⇧ Tab")
        XCTAssertEqual(ShortcutDisplayFormatter.format("option+a"), "⌥ A")
        XCTAssertEqual(ShortcutDisplayFormatter.format(nil), "Not set")
    }

    func testMonitorSelectorSendsWorkspaceAndSelectedMonitor() throws {
        let snapshot = settingsSnapshot()
        var update: (workspace: String, monitorSlot: MonitorSlot)?
        let viewController = WorkspaceSettingsViewController(
            snapshotProvider: { snapshot },
            updateMonitorHandler: { workspace, monitorSlot in
                update = (workspace, monitorSlot)
            },
            addWorkspaceHandler: { _ in },
            removeWorkspaceHandler: { _ in }
        )

        _ = viewController.view
        let selector = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "kkaci.settings.workspace.1.monitor" }
        )
        let targetItem = try XCTUnwrap(selector.itemArray.first { $0.representedObject as? Int == 2 })
        XCTAssertEqual(targetItem.title, "Studio Display")

        selector.select(targetItem)
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(update?.workspace, "1")
        XCTAssertEqual(update?.monitorSlot, 2)
    }

    func testWorkspaceControlsExposeAddAndPreventDeletingTheLastWorkspace() throws {
        let snapshot = settingsSnapshot()
        let viewController = WorkspaceSettingsViewController(
            snapshotProvider: { snapshot },
            updateMonitorHandler: { _, _ in },
            addWorkspaceHandler: { _ in },
            removeWorkspaceHandler: { _ in }
        )

        _ = viewController.view
        let buttons = descendants(of: viewController.view).compactMap { $0 as? NSButton }
        let addButton = try XCTUnwrap(buttons.first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.add"
        })
        let removeButton = try XCTUnwrap(buttons.first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.1.remove"
        })

        XCTAssertTrue(addButton.isEnabled)
        XCTAssertFalse(removeButton.isEnabled)
    }

    func testWorkspaceAddMenuListsAllIDsAtOneLevel() {
        let menu = WorkspaceAddMenu(
            workspaceIDs: ["2", "10", "A"],
            target: self,
            action: #selector(ignoreMenuAction(_:))
        )

        XCTAssertEqual(menu.items.map(\.title), ["2", "10", "A"])
        XCTAssertTrue(menu.items.allSatisfy { $0.submenu == nil })
    }

    private func settingsSnapshot() -> WorkspaceSettingsSnapshot {
        let main = DisplaySnapshot(
            id: 1,
            name: "Built-in Retina Display",
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            role: .main
        )
        let extended = DisplaySnapshot(
            id: 2,
            name: "Studio Display",
            frame: CGRect(x: 1600, y: 0, width: 1200, height: 800),
            role: .extended
        )
        return WorkspaceSettingsSnapshot(
            config: KkaciConfig(
                workspaces: [WorkspaceConfig(id: "1")]
            ),
            monitorSlots: [
                MonitorSlotSnapshot(slot: 1, display: main),
                MonitorSlotSnapshot(slot: 2, display: extended)
            ],
            displays: [main, extended]
        )
    }

    private func snapshotConfig() -> KkaciConfig {
        KkaciConfig(
            workspaces: [
                WorkspaceConfig(
                    id: "1",
                    shortcuts: WorkspaceShortcutConfig(
                        switchWorkspace: "option+1",
                        moveWindow: "option+shift+1"
                    )
                ),
                WorkspaceConfig(id: "A", display: 2),
                WorkspaceConfig(id: "C", display: 3)
            ],
            shortcuts: ShortcutConfig(
                workspaceSwitcher: SwitcherShortcutConfig(
                    next: "ctrl+tab",
                    previous: "ctrl+shift+tab"
                )
            )
        )
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants)
    }

    @objc private func ignoreMenuAction(_: NSMenuItem) {}
}
