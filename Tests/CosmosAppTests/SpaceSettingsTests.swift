import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceSettingsServiceTests: XCTestCase {
    func testServicePersistsAppliesAndRefreshesExplicitSpaceEdits() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let configStore = ConfigStoreSpy(loadedConfig: controller.currentConfig)
        let shortcutInstaller = SpaceSettingsShortcutInstaller()
        let actions = NoopShortcutActions()
        let configRuntime = ConfigRuntime(
            configStore: configStore,
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: shortcutInstaller,
            keyboardBindingMapper: KeyboardBindingMapper()
        )
        var refreshCount = 0
        let service = SpaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actions,
            refreshAfterChange: { refreshCount += 1 }
        )

        try service.addSpaces(["A"], displayID: 1)
        try service.removeSpace("A")

        XCTAssertEqual(configStore.savedConfigs.count, 2)
        XCTAssertTrue(configStore.savedConfigs[0].spaces.map(\.id).contains("A"))
        XCTAssertFalse(configStore.savedConfigs[1].spaces.map(\.id).contains("A"))
        XCTAssertEqual(controller.currentConfig, configStore.savedConfigs[1])
        XCTAssertEqual(shortcutInstaller.replacedKeys.count, 2)
        XCTAssertEqual(refreshCount, 2)
    }

    func testServiceDoesNotPersistOrRefreshAnUnchangedMonitorAssignment() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let configStore = ConfigStoreSpy(loadedConfig: controller.currentConfig)
        let configRuntime = ConfigRuntime(
            configStore: configStore,
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: SpaceSettingsShortcutInstaller(),
            keyboardBindingMapper: KeyboardBindingMapper()
        )
        var refreshCount = 0
        let service = SpaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: NoopShortcutActions(),
            refreshAfterChange: { refreshCount += 1 }
        )

        try service.updateMonitor("1", displayID: 1)
        _ = try service.updateShortcut("option+1", for: .switchSpace("1"))

        XCTAssertTrue(configStore.savedConfigs.isEmpty)
        XCTAssertEqual(refreshCount, 0)
    }

    func testSnapshotCountsAllAssignedWindowsIncludingMinimizedWindows() throws {
        let visible = makeSwitcherTestWindow(id: 10, title: "Visible")
        let laterMinimized = makeSwitcherTestWindow(id: 20, title: "Minimized")
        let (controller, windowSystem) = try makeSwitcherTestController(windows: [visible, laterMinimized])
        windowSystem.replaceWindows([
            visible,
            WindowSnapshot(
                id: laterMinimized.id,
                app: laterMinimized.app,
                title: laterMinimized.title,
                frame: laterMinimized.frame,
                isMinimized: true
            )
        ])
        _ = try controller.handleWindowSetChanged()
        let configStore = ConfigStoreSpy(loadedConfig: controller.currentConfig)
        let service = SpaceSettingsService(
            controller: controller,
            configRuntime: ConfigRuntime(
                configStore: configStore,
                configURL: nil,
                controller: controller,
                keyboardShortcutManager: SpaceSettingsShortcutInstaller(),
                keyboardBindingMapper: KeyboardBindingMapper()
            ),
            actions: NoopShortcutActions(),
            refreshAfterChange: {}
        )

        let space = try XCTUnwrap(service.snapshot().spaces.first { $0.id == "1" })

        XCTAssertEqual(space.windowCount, 2)
    }
}

final class SpaceSettingsSnapshotTests: XCTestCase {
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
        let snapshot = SpaceSettingsSnapshot(
            config: snapshotConfig(),
            monitorSlots: [
                MonitorSlotSnapshot(slot: 1, display: main),
                MonitorSlotSnapshot(slot: 2, display: extended)
            ],
            spaceWindowCounts: ["1": 2, "A": 1]
        )

        XCTAssertEqual(snapshot.displays[0].spaceIDs, ["1"])
        XCTAssertEqual(snapshot.displays[0].name, "Built-in Retina Display")
        XCTAssertEqual(snapshot.displays[1].spaceIDs, ["A"])
        XCTAssertTrue(snapshot.displays.allSatisfy(\.hasUnobstructedParkingCorner))
        XCTAssertEqual(snapshot.disconnectedMonitorSlots, [3])
        XCTAssertEqual(snapshot.spaceSwitcher, "option+shift+tab")
        XCTAssertEqual(snapshot.windowSwitcher, "option+tab")
        XCTAssertEqual(snapshot.spaces[0].switchShortcut, "option+1")
        XCTAssertEqual(snapshot.spaces[0].moveShortcut, "option+shift+1")
        XCTAssertNil(snapshot.spaces[1].switchShortcut)
        XCTAssertEqual(snapshot.spaces.map(\.windowCount), [2, 1, 0])
    }

    func testShortcutFormatterUsesMacModifierSymbols() {
        XCTAssertEqual(ShortcutDisplayFormatter.format("ctrl+shift+tab"), "⌃ ⇧ Tab")
        XCTAssertEqual(ShortcutDisplayFormatter.format("option+a"), "⌥ A")
        XCTAssertEqual(ShortcutDisplayFormatter.format(nil), "-")
    }
}

final class SpaceSettingsViewTests: XCTestCase {
    private enum TestError: Error {
        case shortcutRestore
    }

    func testDisplaySectionIncludesDisplaySettingsButton() throws {
        let viewController = SpaceSettingsViewController(
            service: SpaceSettingsServiceStub(snapshot: settingsSnapshot())
        )

        let button = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.display-settings" }
        )

        XCTAssertEqual(button.title, "Display Settings")
        XCTAssertEqual(button.imagePosition, .imageLeading)
        XCTAssertEqual(button.image?.accessibilityDescription, "Display Settings")
    }

    func testSelectingSpaceOpensInspectorAndMonitorSelectorUpdatesDisplay() throws {
        let snapshot = settingsSnapshot()
        var update: (space: SpaceID, displayID: DisplayID)?
        let service = SpaceSettingsServiceStub(snapshot: snapshot)
        service.onUpdateMonitor = { space, displayID in
            update = (space, displayID)
        }
        let viewController = SpaceSettingsViewController(service: service)

        _ = viewController.view
        let spacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        spacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))

        let selector = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space.1.monitor" }
        )
        let targetItem = try XCTUnwrap(selector.itemArray.first { $0.representedObject as? DisplayID == 2 })
        XCTAssertEqual(targetItem.title, "2 · Studio Display")
        XCTAssertFalse(selector.menu?.autoenablesItems ?? true)
        XCTAssertEqual(selector.bezelStyle, .badge)
        XCTAssertEqual(selector.controlSize, .large)

        selector.select(targetItem)
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(update?.space, "1")
        XCTAssertEqual(update?.displayID, 2)
    }

    func testSelectingDisplayOpensInlineEditorAndAddsSpaceImmediately() throws {
        let snapshot = settingsSnapshot()
        let service = SpaceSettingsServiceStub(snapshot: snapshot)
        var addition: (spaceIDs: [SpaceID], displayID: DisplayID)?
        service.onAddSpaces = { spaceIDs, displayID in
            addition = (spaceIDs, displayID)
        }
        let viewController = SpaceSettingsViewController(service: service)

        _ = viewController.view
        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display.2"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))

        let editor = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space.editor"
        })
        XCTAssertFalse(editor.isHidden)
        let spaceB = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? SpaceIDKeyButton }
                .first { $0.spaceID == "B" }
        )
        spaceB.performClick(nil)

        XCTAssertEqual(addition?.spaceIDs, ["B"])
        XCTAssertEqual(addition?.displayID, 2)
        XCTAssertFalse(editor.isHidden)
    }

    func testSelectingConfiguredKeyOpensSpaceInspector() throws {
        let snapshot = settingsSnapshot(spaces: [
            SpaceConfig(id: "1"),
            SpaceConfig(id: "2")
        ])
        let service = SpaceSettingsServiceStub(snapshot: snapshot)
        let viewController = SpaceSettingsViewController(service: service)

        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display.1"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))
        let configuredSpace = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? SpaceIDKeyButton }
                .first { $0.spaceID == "1" }
        )
        configuredSpace.performClick(nil)

        let inspector = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space.inspector"
        })
        XCTAssertFalse(inspector.isHidden)
        XCTAssertNotNil(descendants(of: inspector).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space.1.remove"
        })
    }

    func testDeleteModeRemovesConfiguredEmptySpace() throws {
        let snapshot = settingsSnapshot(spaces: [
            SpaceConfig(id: "1"),
            SpaceConfig(id: "2")
        ])
        let service = SpaceSettingsServiceStub(snapshot: snapshot)
        var removedSpace: SpaceID?
        service.onRemoveSpace = { removedSpace = $0 }
        let viewController = SpaceSettingsViewController(service: service)

        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display.1"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))
        let deleteMode = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space.delete-mode" }
        )
        deleteMode.performClick(nil)
        let configuredSpace = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? SpaceIDKeyButton }
                .first { $0.spaceID == "1" }
        )
        configuredSpace.performClick(nil)

        XCTAssertEqual(deleteMode.state, .on)
        XCTAssertEqual(removedSpace, "1")
    }

    func testDeletingSpaceWithWindowsRequiresIconlessConfirmation() throws {
        let snapshot = settingsSnapshot(
            spaces: [SpaceConfig(id: "1"), SpaceConfig(id: "2")],
            spaceWindowCounts: ["1": 1]
        )
        let service = SpaceSettingsServiceStub(snapshot: snapshot)
        var removedSpace: SpaceID?
        service.onRemoveSpace = { removedSpace = $0 }
        let viewController = SpaceSettingsViewController(service: service)
        let window = NSWindow(contentViewController: viewController)
        defer { window.close() }

        let spacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        spacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        let removeButton = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space.1.remove" }
        )
        removeButton.performClick(nil)

        let sheet = try XCTUnwrap(window.attachedSheet)
        let visibleIcons = try descendants(of: XCTUnwrap(sheet.contentView))
            .compactMap { $0 as? NSImageView }
            .filter { !$0.isHidden }
        XCTAssertTrue(visibleIcons.isEmpty)
        XCTAssertNil(removedSpace)

        let deleteButton = try XCTUnwrap(
            try descendants(of: XCTUnwrap(sheet.contentView))
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Delete" }
        )
        deleteButton.performClick(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(removedSpace, "1")
    }

    func testSpaceInspectorExposesSpaceRecordersOnlyAfterSelection() throws {
        let snapshot = settingsSnapshot()
        let viewController = SpaceSettingsViewController(
            service: SpaceSettingsServiceStub(snapshot: snapshot)
        )

        var recorders = descendants(of: viewController.view).compactMap { $0 as? ShortcutRecorderButton }
        XCTAssertTrue(recorders.isEmpty)

        let spacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        spacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        recorders = descendants(of: viewController.view).compactMap { $0 as? ShortcutRecorderButton }

        XCTAssertEqual(Set(recorders.map(\.shortcutTarget)), Set([
            .switchSpace("1"),
            .moveWindow("1")
        ]))
    }

    func testSwitcherSettingsExposeCycleRecorders() throws {
        let service = SpaceSettingsServiceStub(snapshot: settingsSnapshot())
        let suiteName = "SwitcherSettingsViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewController = SwitcherSettingsViewController(
            store: AppSettingsStore(defaults: defaults),
            settingsService: service,
            shortcutRecordingController: ShortcutRecordingController(service: service),
            onChange: {}
        )

        let recorders = descendants(of: viewController.view).compactMap { $0 as? ShortcutRecorderButton }
        let labels = descendants(of: viewController.view)
            .compactMap { $0 as? NSTextField }
            .map(\.stringValue)

        XCTAssertEqual(recorders.map(\.shortcutTarget), [
            .spaceSwitcher,
            .windowSwitcher
        ])
        XCTAssertTrue(labels.contains("Space"))
        XCTAssertTrue(labels.contains("Window"))
        XCTAssertEqual(labels.filter { $0 == "Cycle Keybinding" }.count, 2)
        XCTAssertEqual(labels.filter { $0 == "Switcher Size" }.count, 2)
    }

    func testClickingDisplayCardOutsideASpaceClearsTheInspector() throws {
        let viewController = SpaceSettingsViewController(
            service: SpaceSettingsServiceStub(snapshot: settingsSnapshot())
        )

        let spacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        spacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        XCTAssertFalse(try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space.inspector"
        }).isHidden)

        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display.1"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))

        XCTAssertTrue(try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space.inspector"
        }).isHidden)
    }

    func testUnreadableConfigDisablesSpaceEditing() throws {
        let main = DisplaySnapshot(
            id: 1,
            name: "Built-in Retina Display",
            frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
            role: .main
        )
        let snapshot = SpaceSettingsSnapshot(
            config: CosmosConfig(spaces: [SpaceConfig(id: "1")]),
            monitorSlots: [MonitorSlotSnapshot(slot: 1, display: main)],
            isEditable: false
        )
        let viewController = SpaceSettingsViewController(
            service: SpaceSettingsServiceStub(snapshot: snapshot)
        )

        let controls = descendants(of: viewController.view).compactMap { $0 as? NSControl }

        XCTAssertTrue(
            controls
                .compactMap { $0 as? SpaceIDKeyButton }
                .allSatisfy { !$0.isEnabled }
        )
        XCTAssertTrue(controls.compactMap { $0 as? ShortcutRecorderButton }.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(
            try XCTUnwrap(controls.compactMap { $0 as? NSTextField }.first {
                $0.accessibilityIdentifier() == "cosmos.settings.space.config-error"
            }).stringValue,
            "Configuration is invalid. Fix config.yaml in General before editing spaces."
        )
    }

    func testSpaceEditingRecoversAfterConfigBecomesReadable() throws {
        let service = SpaceSettingsServiceStub(snapshot: settingsSnapshot(isEditable: false))
        let viewController = SpaceSettingsViewController(service: service)

        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display.1"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))
        let deleteModeButton = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space.delete-mode" }
        )
        let availableSpaceButton = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? SpaceIDKeyButton }
                .first { $0.spaceID == "B" }
        )
        XCTAssertFalse(deleteModeButton.isEnabled)
        XCTAssertFalse(availableSpaceButton.isEnabled)

        service.snapshotValue = settingsSnapshot(isEditable: true)
        viewController.refresh()

        XCTAssertTrue(deleteModeButton.isEnabled)
        XCTAssertTrue(availableSpaceButton.isEnabled)
    }

    func testRefreshKeepsTheCurrentRecorderWhenShortcutRestoreFails() throws {
        let service = SpaceSettingsServiceStub(snapshot: settingsSnapshot())
        service.cancelShortcutRecordingError = TestError.shortcutRestore
        let viewController = SpaceSettingsViewController(service: service)
        let spacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        spacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        let recorder = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? ShortcutRecorderButton }
                .first
        )
        recorder.performClick(nil)
        XCTAssertTrue(recorder.isRecording)

        viewController.refresh()

        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(descendants(of: viewController.view).contains { $0 === recorder })
    }
}

final class SpaceIDPickerTests: XCTestCase {
    func testSpaceIDPickerDistinguishesConfiguredAndAvailableSelections() throws {
        let picker = SpaceIDPickerView()
        picker.apply(
            monitorSlotBySpaceID: ["1": 1, "A": 1, "C": 2],
            selectedMonitorSlot: 1
        )
        var availableSelection: SpaceID?
        var configuredSelection: SpaceID?
        var removalSelection: SpaceID?
        picker.onSpaceSelected = { availableSelection = $0 }
        picker.onConfiguredSpaceSelected = { configuredSelection = $0 }
        picker.onSpaceRemovalRequested = { removalSelection = $0 }
        var deleteMode = false
        picker.onDeleteModeChanged = { deleteMode = $0 }
        let buttons = descendants(of: picker).compactMap { $0 as? SpaceIDKeyButton }
        let zero = try XCTUnwrap(buttons.first { $0.spaceID == "0" })
        let one = try XCTUnwrap(buttons.first { $0.spaceID == "1" })
        let letterA = try XCTUnwrap(buttons.first { $0.spaceID == "A" })
        let letterB = try XCTUnwrap(buttons.first { $0.spaceID == "B" })
        let letterC = try XCTUnwrap(buttons.first { $0.spaceID == "C" })

        XCTAssertTrue(zero.isEnabled)
        XCTAssertTrue(one.isEnabled)
        XCTAssertTrue(letterA.isEnabled)
        XCTAssertFalse(letterC.isEnabled)
        XCTAssertEqual(letterC.toolTip, "Assigned to Display 2")

        letterA.performClick(nil)
        zero.performClick(nil)
        letterB.performClick(nil)

        XCTAssertEqual(configuredSelection, "A")
        XCTAssertEqual(availableSelection, "B")

        let deleteButton = try XCTUnwrap(
            descendants(of: picker)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space.delete-mode" }
        )
        deleteButton.performClick(nil)
        XCTAssertTrue(deleteMode)

        picker.apply(
            monitorSlotBySpaceID: ["1": 1, "A": 1, "C": 2],
            selectedMonitorSlot: 1,
            isDeleteMode: deleteMode
        )
        XCTAssertFalse(zero.isEnabled)
        XCTAssertTrue(one.isEnabled)
        XCTAssertFalse(letterC.isEnabled)
        one.performClick(nil)

        XCTAssertEqual(removalSelection, "1")
    }

    func testSpaceIDPickerCentersTheKeyboard() {
        let picker = SpaceIDPickerView()
        picker.frame = NSRect(x: 0, y: 0, width: 520, height: 184)
        picker.layoutSubtreeIfNeeded()

        let buttons = descendants(of: picker).compactMap { $0 as? SpaceIDKeyButton }
        let frames = buttons.map { picker.convert($0.bounds, from: $0) }
        let keyboardFrame = frames.reduce(NSRect.null) { $0.union($1) }

        XCTAssertEqual(keyboardFrame.midX, picker.bounds.midX, accuracy: 1)

        let deleteButton = descendants(of: picker)
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityIdentifier() == "cosmos.settings.space.delete-mode" }
        XCTAssertEqual(deleteButton?.frame.width, 32)
        XCTAssertEqual(deleteButton?.frame.height, 32)
        XCTAssertEqual(deleteButton?.frame.maxX, picker.bounds.maxX)
        XCTAssertEqual(deleteButton?.frame.minY, picker.bounds.minY)
    }
}

extension SpaceSettingsViewTests {
    func testShortcutConflictsStayOnRecorderControlsWithoutASeparateSection() {
        let base = settingsSnapshot()
        let snapshot = SpaceSettingsSnapshot(
            config: CosmosConfig(spaces: [SpaceConfig(id: "1")]),
            monitorSlots: base.displays.map { display in
                MonitorSlotSnapshot(
                    slot: display.monitorSlot,
                    display: DisplaySnapshot(
                        id: display.id,
                        name: display.name,
                        frame: display.frame,
                        role: display.role
                    )
                )
            },
            shortcutValidationMessages: [
                .switchSpace("1"): "Already assigned to \"Cycle Space\"."
            ]
        )
        let viewController = SpaceSettingsViewController(
            service: SpaceSettingsServiceStub(snapshot: snapshot)
        )

        XCTAssertNil(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "cosmos.settings.shortcut-conflicts"
        })
    }
}

final class SpaceDisplayArrangementTests: XCTestCase {
    func testSpaceDragPayloadRoundTripsSpaceID() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("cosmos.space-test"))
        pasteboard.clearContents()
        pasteboard.writeObjects([SpaceDragPayload.pasteboardItem(for: "A")])

        XCTAssertEqual(SpaceDragPayload.spaceID(from: pasteboard), "A")
    }

    func testDisplayArrangementHitTestsTheSpaceUnderThePointer() throws {
        let display = SpaceSettingsDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            spaceIDs: ["1", "Y"]
        )
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [display],
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let one = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.1"
        })
        let letterY = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.space-pill.Y"
        })
        let onePoint = NSPoint(x: one.frame.midX, y: one.frame.midY)
        let letterYPoint = NSPoint(x: letterY.frame.midX, y: letterY.frame.midY)

        XCTAssertTrue(one.hitTest(onePoint) === one)
        XCTAssertTrue(letterY.hitTest(letterYPoint) === letterY)
        XCTAssertNil(one.hitTest(letterYPoint))
        XCTAssertNil(letterY.hitTest(onePoint))
    }

    func testDisplayArrangementShowsOverflowInsteadOfDroppingSpaceIDs() throws {
        let display = SpaceSettingsDisplay(
            id: 1,
            name: "Small Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            spaceIDs: SpaceID.allCases
        )
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 260, height: 140))
        arrangement.apply(
            [display],
            selectedDisplayID: 1,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let overflow = try XCTUnwrap(
            descendants(of: arrangement)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "cosmos.settings.space-overflow" }
        )
        XCTAssertFalse(overflow.isHidden)
        XCTAssertTrue(overflow.title.hasPrefix("+"))
    }

    func testDisplayArrangementShowsParkingWarningForObstructedDisplay() throws {
        let obstructed = SpaceSettingsDisplay(
            id: 1,
            name: "Center Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            spaceIDs: ["1"],
            hasUnobstructedParkingCorner: false
        )
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [obstructed],
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )

        let warning = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display-parking-warning.1"
        })

        XCTAssertFalse(warning.isHidden)
        XCTAssertEqual(
            warning.toolTip,
            "No unobstructed parking corner is available. "
                + "Hidden windows may remain visible and clickable on another display. "
                + "Rearrange the displays in System Settings."
        )
    }

    func testDisplayArrangementHidesParkingWarningForSafeDisplays() throws {
        let arrangement = SpaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [settingsSnapshot().displays[0]],
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )

        let warning = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "cosmos.settings.display-parking-warning.1"
        })

        XCTAssertTrue(warning.isHidden)
        XCTAssertNil(warning.toolTip)
    }

    func testDisplayArrangementPreservesMinimumCardSizeAndExpandsForVerticalLayouts() throws {
        let displays = [
            SpaceSettingsDisplay(
                id: 1,
                name: "Top",
                frame: CGRect(x: 0, y: 900, width: 1440, height: 900),
                role: .main,
                monitorSlot: 1,
                spaceIDs: ["1"]
            ),
            SpaceSettingsDisplay(
                id: 2,
                name: "Bottom",
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                role: .extended,
                monitorSlot: 2,
                spaceIDs: ["2"]
            )
        ]
        let arrangement = SpaceDisplayArrangementView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 210)
        )
        arrangement.apply(
            displays,
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let cards = try displays.map { display in
            try XCTUnwrap(descendants(of: arrangement).first {
                $0.accessibilityIdentifier() == "cosmos.settings.display.\(display.monitorSlot)"
            })
        }
        XCTAssertTrue(cards.allSatisfy { $0.frame.width >= 210 })
        XCTAssertTrue(cards.allSatisfy { $0.frame.height >= 130 })
        XCTAssertGreaterThan(arrangement.intrinsicContentSize.height, 210)
    }

    func testDisplayArrangementScrollsInsteadOfShrinkingWideLayouts() throws {
        let displays = (0 ..< 3).map { index in
            SpaceSettingsDisplay(
                id: DisplayID(index + 1),
                name: "Display \(index + 1)",
                frame: CGRect(x: index * 1440, y: 0, width: 1440, height: 900),
                role: index == 0 ? .main : .extended,
                monitorSlot: index + 1,
                spaceIDs: [SpaceID.allCases[index + 1]]
            )
        }
        let arrangement = SpaceDisplayArrangementView(
            frame: NSRect(x: 0, y: 0, width: 360, height: 210)
        )
        arrangement.apply(
            displays,
            selectedDisplayID: nil,
            selectedSpaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(descendants(of: arrangement).compactMap { $0 as? NSScrollView }.first)
        let documentView = try XCTUnwrap(scrollView.documentView)

        XCTAssertGreaterThan(documentView.frame.width, scrollView.contentSize.width)
        XCTAssertTrue(displays.allSatisfy { display in
            descendants(of: arrangement).first {
                $0.accessibilityIdentifier() == "cosmos.settings.display.\(display.monitorSlot)"
            }.map { $0.frame.width >= 210 } ?? false
        })
    }
}

private func mouseEvent(type: NSEvent.EventType) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    )!
}

private func settingsSnapshot(
    spaces: [SpaceConfig] = [SpaceConfig(id: "1")],
    spaceWindowCounts: [SpaceID: Int] = [:],
    isEditable: Bool = true
) -> SpaceSettingsSnapshot {
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
    return SpaceSettingsSnapshot(
        config: CosmosConfig(spaces: spaces),
        monitorSlots: [
            MonitorSlotSnapshot(slot: 1, display: main),
            MonitorSlotSnapshot(slot: 2, display: extended)
        ],
        spaceWindowCounts: spaceWindowCounts,
        isEditable: isEditable
    )
}

private func snapshotConfig() -> CosmosConfig {
    CosmosConfig(
        spaces: [
            SpaceConfig(
                id: "1",
                shortcuts: SpaceShortcutConfig(
                    switchSpace: "option+1",
                    moveWindow: "option+shift+1"
                )
            ),
            SpaceConfig(id: "A", display: 2),
            SpaceConfig(id: "C", display: 3)
        ],
        switcher: SwitcherConfig(
            shortcuts: SwitcherShortcutConfig(
                space: "option+shift+tab",
                window: "option+tab"
            )
        )
    )
}

private func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants)
}

private final class SpaceSettingsServiceStub: SpaceSettingsServing {
    var snapshotValue: SpaceSettingsSnapshot
    var onUpdateMonitor: (SpaceID, DisplayID) throws -> Void = { _, _ in }
    var onAddSpaces: ([SpaceID], DisplayID) throws -> Void = { _, _ in }
    var onRemoveSpace: (SpaceID) throws -> Void = { _ in }
    var cancelShortcutRecordingError: Error?

    init(snapshot: SpaceSettingsSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> SpaceSettingsSnapshot {
        snapshotValue
    }

    func updateShortcut(_: String?, for _: ShortcutTarget) throws -> Bool {
        false
    }

    func updateMonitor(_ spaceID: SpaceID, displayID: DisplayID) throws {
        try onUpdateMonitor(spaceID, displayID)
    }

    func addSpaces(_ spaceIDs: [SpaceID], displayID: DisplayID) throws {
        try onAddSpaces(spaceIDs, displayID)
    }

    func removeSpace(_ spaceID: SpaceID) throws {
        try onRemoveSpace(spaceID)
    }

    func beginShortcutRecording() throws {}

    func cancelShortcutRecording() throws {
        if let cancelShortcutRecordingError {
            throw cancelShortcutRecordingError
        }
    }

    func shortcutRecordingDidFinish(didPersistChange _: Bool) {}
}

private final class SpaceSettingsShortcutInstaller: KeyboardShortcutInstalling {
    private(set) var replacedKeys: [[String]] = []

    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws {
        _ = try KeyboardShortcutResolver().resolve(registrations)
        replacedKeys.append(registrations.map(\.key))
    }
}
