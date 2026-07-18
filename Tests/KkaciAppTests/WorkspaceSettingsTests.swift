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
        let snapshot = WorkspaceSettingsSnapshot(
            config: snapshotConfig(),
            monitorSlots: [
                MonitorSlotSnapshot(slot: 1, display: main),
                MonitorSlotSnapshot(slot: 2, display: extended)
            ],
            displays: [main, extended]
        )

        XCTAssertEqual(snapshot.displays[0].workspaceIDs, ["1"])
        XCTAssertEqual(snapshot.displays[0].workspaceTitles, ["Develop (1)"])
        XCTAssertEqual(snapshot.displays[0].name, "Built-in Retina Display")
        XCTAssertEqual(snapshot.displays[1].workspaceIDs, ["A"])
        XCTAssertEqual(snapshot.disconnectedMonitorSlots, [3])
        XCTAssertEqual(snapshot.workspaceSwitcher.next, "ctrl+tab")
        XCTAssertEqual(snapshot.workspaceSwitcher.previous, "ctrl+shift+tab")
        XCTAssertEqual(snapshot.windowSwitcher.next, "option+tab")
        XCTAssertEqual(snapshot.windowSwitcher.previous, "option+shift+tab")
        XCTAssertEqual(snapshot.workspaces[0].switchShortcut, "option+1")
        XCTAssertEqual(snapshot.workspaces[0].displayTitle, "Develop (1)")
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
        var update: (workspace: String, displayID: DisplayID)?
        let viewController = WorkspaceSettingsViewController(
            snapshotProvider: { snapshot },
            updateMonitorHandler: { workspace, displayID in
                update = (workspace, displayID)
            },
            addWorkspaceHandler: { _, _ in },
            removeWorkspaceHandler: { _ in },
            updateNameHandler: { _, _ in },
            beginShortcutRecordingHandler: {},
            cancelShortcutRecordingHandler: {},
            updateShortcutHandler: { _, _ in }
        )

        _ = viewController.view
        let selector = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "kkaci.settings.workspace.1.monitor" }
        )
        let targetItem = try XCTUnwrap(selector.itemArray.first { $0.representedObject as? DisplayID == 2 })
        XCTAssertEqual(targetItem.title, "2 · Studio Display")
        XCTAssertFalse(selector.menu?.autoenablesItems ?? true)

        selector.select(targetItem)
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(update?.workspace, "1")
        XCTAssertEqual(update?.displayID, 2)
    }

    func testWorkspaceControlsExposeAddAndPreventDeletingTheLastWorkspace() throws {
        let snapshot = settingsSnapshot()
        let viewController = WorkspaceSettingsViewController(
            snapshotProvider: { snapshot },
            updateMonitorHandler: { _, _ in },
            addWorkspaceHandler: { _, _ in },
            removeWorkspaceHandler: { _ in },
            updateNameHandler: { _, _ in },
            beginShortcutRecordingHandler: {},
            cancelShortcutRecordingHandler: {},
            updateShortcutHandler: { _, _ in }
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

    func testWorkspaceSettingsExposeRecordersForEveryShortcutTarget() {
        let snapshot = settingsSnapshot()
        let viewController = WorkspaceSettingsViewController(
            snapshotProvider: { snapshot },
            updateMonitorHandler: { _, _ in },
            addWorkspaceHandler: { _, _ in },
            removeWorkspaceHandler: { _ in },
            updateNameHandler: { _, _ in },
            beginShortcutRecordingHandler: {},
            cancelShortcutRecordingHandler: {},
            updateShortcutHandler: { _, _ in }
        )

        let recorders = descendants(of: viewController.view).compactMap { $0 as? ShortcutRecorderButton }

        XCTAssertEqual(recorders.map(\.shortcutTarget), [
            .workspaceSwitcherNext,
            .workspaceSwitcherPrevious,
            .windowSwitcherNext,
            .windowSwitcherPrevious,
            .switchWorkspace("1"),
            .moveWindow("1")
        ])
    }

    func testUnreadableConfigDisablesWorkspaceEditing() throws {
        let main = DisplaySnapshot(
            id: 1,
            name: "Built-in Retina Display",
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            role: .main
        )
        let snapshot = WorkspaceSettingsSnapshot(
            config: KkaciConfig(workspaces: [WorkspaceConfig(id: "1")]),
            monitorSlots: [MonitorSlotSnapshot(slot: 1, display: main)],
            displays: [main],
            isEditable: false
        )
        let viewController = WorkspaceSettingsViewController(
            snapshotProvider: { snapshot },
            updateMonitorHandler: { _, _ in },
            addWorkspaceHandler: { _, _ in },
            removeWorkspaceHandler: { _ in },
            updateNameHandler: { _, _ in },
            beginShortcutRecordingHandler: {},
            cancelShortcutRecordingHandler: {},
            updateShortcutHandler: { _, _ in }
        )

        let controls = descendants(of: viewController.view).compactMap { $0 as? NSControl }

        XCTAssertFalse(try XCTUnwrap(controls.first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.add"
        }).isEnabled)
        XCTAssertFalse(try XCTUnwrap(controls.first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.1.name"
        }).isEnabled)
        XCTAssertTrue(controls.compactMap { $0 as? ShortcutRecorderButton }.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(
            try XCTUnwrap(controls.compactMap { $0 as? NSTextField }.first {
                $0.accessibilityIdentifier() == "kkaci.settings.workspace.config-error"
            }).stringValue,
            "Configuration is invalid. Fix config.yaml in General before editing workspaces."
        )
    }

    func testWorkspaceIDPickerDimsConfiguredIDsAndSelectsAvailableIDs() throws {
        let picker = WorkspaceIDPickerView(unavailableWorkspaceIDs: ["1", "A"])
        let buttons = descendants(of: picker).compactMap { $0 as? WorkspaceIDKeyButton }
        let zero = try XCTUnwrap(buttons.first { $0.workspaceID == "0" })
        let one = try XCTUnwrap(buttons.first { $0.workspaceID == "1" })
        let letterA = try XCTUnwrap(buttons.first { $0.workspaceID == "A" })
        let letterB = try XCTUnwrap(buttons.first { $0.workspaceID == "B" })

        XCTAssertTrue(zero.isEnabled)
        XCTAssertFalse(one.isEnabled)
        XCTAssertFalse(letterA.isEnabled)

        zero.performClick(nil)
        letterB.performClick(nil)

        XCTAssertEqual(picker.selectedWorkspaceIDs, ["0", "B"])
    }

    func testWorkspaceIDPickerAddsSelectedIDsToTheChosenDisplay() throws {
        var addition: (workspaceIDs: [WorkspaceID], displayID: DisplayID)?
        let viewController = WorkspaceIDPickerViewController(
            unavailableWorkspaceIDs: ["1"],
            displayOptions: [
                WorkspaceDisplayOption(
                    displayID: 1,
                    monitorSlot: 1,
                    name: "Built-in Retina Display"
                ),
                WorkspaceDisplayOption(displayID: 2, monitorSlot: 2, name: "Studio Display")
            ],
            addHandler: { workspaceIDs, displayID in
                addition = (workspaceIDs, displayID)
            }
        )
        let parent = NSViewController()
        let window = NSWindow(contentViewController: parent)
        defer { window.close() }
        parent.presentAsSheet(viewController)

        _ = viewController.view
        let views = descendants(of: viewController.view)
        let displaySelector = try XCTUnwrap(views.compactMap { $0 as? NSPopUpButton }.first {
            $0.accessibilityIdentifier() == "kkaci.workspace-picker.display"
        })
        XCTAssertEqual(
            displaySelector.itemTitles,
            ["1 · Built-in Retina Display", "2 · Studio Display"]
        )
        XCTAssertFalse(displaySelector.menu?.autoenablesItems ?? true)
        displaySelector.selectItem(at: 1)

        let workspaceB = try XCTUnwrap(views.compactMap { $0 as? WorkspaceIDKeyButton }.first {
            $0.workspaceID == "B"
        })
        workspaceB.performClick(nil)
        let addButton = try XCTUnwrap(views.compactMap { $0 as? NSButton }.first {
            $0.title == "Add Workspaces"
        })
        addButton.performClick(nil)

        XCTAssertEqual(addition?.workspaceIDs, ["B"])
        XCTAssertEqual(addition?.displayID, 2)
    }
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
                name: "Develop",
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
            ),
            windowSwitcher: SwitcherShortcutConfig(
                next: "option+tab",
                previous: "option+shift+tab"
            )
        )
    )
}

private func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants)
}
