import AppKit
import CoreGraphics
@testable import KkaciApp
import KkaciCore
import XCTest

final class WorkspaceSettingsServiceTests: XCTestCase {
    func testServicePersistsAppliesAndRefreshesExplicitWorkspaceEdits() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let configStore = ConfigStoreSpy(loadedConfig: controller.currentConfig)
        let shortcutInstaller = WorkspaceSettingsShortcutInstaller()
        let actions = NoopShortcutActions()
        let configRuntime = ConfigRuntime(
            configStore: configStore,
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: shortcutInstaller,
            keyboardBindingMapper: KeyboardBindingMapper()
        )
        var refreshCount = 0
        let service = WorkspaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actions,
            refreshAfterChange: { refreshCount += 1 }
        )

        try service.addWorkspaces(["A"], displayID: 1)
        try service.removeWorkspace("A")

        XCTAssertEqual(configStore.savedConfigs.count, 2)
        XCTAssertTrue(configStore.savedConfigs[0].workspaces.map(\.id).contains("A"))
        XCTAssertFalse(configStore.savedConfigs[1].workspaces.map(\.id).contains("A"))
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
            keyboardShortcutManager: WorkspaceSettingsShortcutInstaller(),
            keyboardBindingMapper: KeyboardBindingMapper()
        )
        var refreshCount = 0
        let service = WorkspaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: NoopShortcutActions(),
            refreshAfterChange: { refreshCount += 1 }
        )

        try service.updateMonitor("1", displayID: 1)
        _ = try service.updateShortcut("option+1", for: .switchWorkspace("1"))

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
        let service = WorkspaceSettingsService(
            controller: controller,
            configRuntime: ConfigRuntime(
                configStore: configStore,
                configURL: nil,
                controller: controller,
                keyboardShortcutManager: WorkspaceSettingsShortcutInstaller(),
                keyboardBindingMapper: KeyboardBindingMapper()
            ),
            actions: NoopShortcutActions(),
            refreshAfterChange: {}
        )

        let workspace = try XCTUnwrap(service.snapshot().workspaces.first { $0.id == "1" })

        XCTAssertEqual(workspace.windowCount, 2)
    }
}

final class WorkspaceSettingsSnapshotTests: XCTestCase {
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
            workspaceWindowCounts: ["1": 2, "A": 1]
        )

        XCTAssertEqual(snapshot.displays[0].workspaceIDs, ["1"])
        XCTAssertEqual(snapshot.displays[0].name, "Built-in Retina Display")
        XCTAssertEqual(snapshot.displays[1].workspaceIDs, ["A"])
        XCTAssertEqual(snapshot.disconnectedMonitorSlots, [3])
        XCTAssertEqual(snapshot.workspaceSwitcher.next, "ctrl+tab")
        XCTAssertEqual(snapshot.workspaceSwitcher.previous, "ctrl+shift+tab")
        XCTAssertEqual(snapshot.windowSwitcher.next, "option+tab")
        XCTAssertEqual(snapshot.windowSwitcher.previous, "option+shift+tab")
        XCTAssertEqual(snapshot.workspaces[0].switchShortcut, "option+1")
        XCTAssertEqual(snapshot.workspaces[0].moveShortcut, "option+shift+1")
        XCTAssertNil(snapshot.workspaces[1].switchShortcut)
        XCTAssertEqual(snapshot.workspaces.map(\.windowCount), [2, 1, 0])
        XCTAssertFalse(snapshot.availableWorkspaceIDs.contains("1"))
        XCTAssertFalse(snapshot.availableWorkspaceIDs.contains("A"))
        XCTAssertTrue(snapshot.availableWorkspaceIDs.contains("B"))
    }

    func testShortcutFormatterUsesMacModifierSymbols() {
        XCTAssertEqual(ShortcutDisplayFormatter.format("ctrl+shift+tab"), "⌃ ⇧ Tab")
        XCTAssertEqual(ShortcutDisplayFormatter.format("option+a"), "⌥ A")
        XCTAssertEqual(ShortcutDisplayFormatter.format(nil), "-")
    }
}

final class WorkspaceSettingsViewTests: XCTestCase {
    private enum TestError: Error {
        case shortcutRestore
    }

    func testSelectingWorkspaceOpensInspectorAndMonitorSelectorUpdatesDisplay() throws {
        let snapshot = settingsSnapshot()
        var update: (workspace: WorkspaceID, displayID: DisplayID)?
        let service = WorkspaceSettingsServiceStub(snapshot: snapshot)
        service.onUpdateMonitor = { workspace, displayID in
            update = (workspace, displayID)
        }
        let viewController = WorkspaceSettingsViewController(service: service)

        _ = viewController.view
        let workspacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.1"
        })
        workspacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))

        let selector = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.accessibilityIdentifier() == "kkaci.settings.workspace.1.monitor" }
        )
        let targetItem = try XCTUnwrap(selector.itemArray.first { $0.representedObject as? DisplayID == 2 })
        XCTAssertEqual(targetItem.title, "2 · Studio Display")
        XCTAssertFalse(selector.menu?.autoenablesItems ?? true)
        XCTAssertEqual(selector.bezelStyle, .badge)
        XCTAssertEqual(selector.controlSize, .large)

        selector.select(targetItem)
        selector.sendAction(selector.action, to: selector.target)

        XCTAssertEqual(update?.workspace, "1")
        XCTAssertEqual(update?.displayID, 2)
    }

    func testSelectingDisplayOpensInlineEditorAndAddsWorkspaceImmediately() throws {
        let snapshot = settingsSnapshot()
        let service = WorkspaceSettingsServiceStub(snapshot: snapshot)
        var addition: (workspaceIDs: [WorkspaceID], displayID: DisplayID)?
        service.onAddWorkspaces = { workspaceIDs, displayID in
            addition = (workspaceIDs, displayID)
        }
        let viewController = WorkspaceSettingsViewController(service: service)

        _ = viewController.view
        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.display.2"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))

        let editor = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.editor"
        })
        XCTAssertFalse(editor.isHidden)
        let workspaceB = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? WorkspaceIDKeyButton }
                .first { $0.workspaceID == "B" }
        )
        workspaceB.performClick(nil)

        XCTAssertEqual(addition?.workspaceIDs, ["B"])
        XCTAssertEqual(addition?.displayID, 2)
        XCTAssertFalse(editor.isHidden)
    }

    func testSelectingConfiguredKeyImmediatelyDeletesAnEmptyWorkspace() throws {
        let snapshot = settingsSnapshot(workspaces: [
            WorkspaceConfig(id: "1"),
            WorkspaceConfig(id: "2")
        ])
        let service = WorkspaceSettingsServiceStub(snapshot: snapshot)
        var removedWorkspace: WorkspaceID?
        service.onRemoveWorkspace = { removedWorkspace = $0 }
        let viewController = WorkspaceSettingsViewController(service: service)

        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.display.1"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))
        let configuredWorkspace = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? WorkspaceIDKeyButton }
                .first { $0.workspaceID == "1" }
        )
        configuredWorkspace.performClick(nil)

        XCTAssertEqual(removedWorkspace, "1")
    }

    func testDeletingWorkspaceWithWindowsRequiresIconlessConfirmation() throws {
        let snapshot = settingsSnapshot(
            workspaces: [WorkspaceConfig(id: "1"), WorkspaceConfig(id: "2")],
            workspaceWindowCounts: ["1": 1]
        )
        let service = WorkspaceSettingsServiceStub(snapshot: snapshot)
        var removedWorkspace: WorkspaceID?
        service.onRemoveWorkspace = { removedWorkspace = $0 }
        let viewController = WorkspaceSettingsViewController(service: service)
        let window = NSWindow(contentViewController: viewController)
        defer { window.close() }

        let workspacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.1"
        })
        workspacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        let removeButton = try XCTUnwrap(
            descendants(of: viewController.view)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "kkaci.settings.workspace.1.remove" }
        )
        removeButton.performClick(nil)

        let sheet = try XCTUnwrap(window.attachedSheet)
        let visibleIcons = try descendants(of: XCTUnwrap(sheet.contentView))
            .compactMap { $0 as? NSImageView }
            .filter { !$0.isHidden }
        XCTAssertTrue(visibleIcons.isEmpty)
        XCTAssertNil(removedWorkspace)

        let deleteButton = try XCTUnwrap(
            try descendants(of: XCTUnwrap(sheet.contentView))
                .compactMap { $0 as? NSButton }
                .first { $0.title == "Delete" }
        )
        deleteButton.performClick(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(removedWorkspace, "1")
    }

    func testWorkspaceInspectorExposesWorkspaceRecordersOnlyAfterSelection() throws {
        let snapshot = settingsSnapshot()
        let viewController = WorkspaceSettingsViewController(
            service: WorkspaceSettingsServiceStub(snapshot: snapshot)
        )

        var recorders = descendants(of: viewController.view).compactMap { $0 as? ShortcutRecorderButton }
        XCTAssertTrue(recorders.isEmpty)

        let workspacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.1"
        })
        workspacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        recorders = descendants(of: viewController.view).compactMap { $0 as? ShortcutRecorderButton }

        XCTAssertEqual(Set(recorders.map(\.shortcutTarget)), Set([
            .switchWorkspace("1"),
            .moveWindow("1")
        ]))
    }

    func testSwitcherSettingsExposeCycleRecorders() throws {
        let service = WorkspaceSettingsServiceStub(snapshot: settingsSnapshot())
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

        XCTAssertEqual(recorders.map(\.shortcutTarget), [
            .workspaceSwitcherNext,
            .workspaceSwitcherPrevious,
            .windowSwitcherNext,
            .windowSwitcherPrevious
        ])
    }

    func testClickingDisplayCardOutsideAWorkspaceClearsTheInspector() throws {
        let viewController = WorkspaceSettingsViewController(
            service: WorkspaceSettingsServiceStub(snapshot: settingsSnapshot())
        )

        let workspacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.1"
        })
        workspacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
        XCTAssertFalse(try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.inspector"
        }).isHidden)

        let displayCard = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.display.1"
        })
        displayCard.mouseDown(with: mouseEvent(type: .leftMouseDown))

        XCTAssertTrue(try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace.inspector"
        }).isHidden)
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
            isEditable: false
        )
        let viewController = WorkspaceSettingsViewController(
            service: WorkspaceSettingsServiceStub(snapshot: snapshot)
        )

        let controls = descendants(of: viewController.view).compactMap { $0 as? NSControl }

        XCTAssertTrue(
            controls
                .compactMap { $0 as? WorkspaceIDKeyButton }
                .allSatisfy { !$0.isEnabled }
        )
        XCTAssertTrue(controls.compactMap { $0 as? ShortcutRecorderButton }.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(
            try XCTUnwrap(controls.compactMap { $0 as? NSTextField }.first {
                $0.accessibilityIdentifier() == "kkaci.settings.workspace.config-error"
            }).stringValue,
            "Configuration is invalid. Fix config.yaml in General before editing workspaces."
        )
    }

    func testRefreshKeepsTheCurrentRecorderWhenShortcutRestoreFails() throws {
        let service = WorkspaceSettingsServiceStub(snapshot: settingsSnapshot())
        service.cancelShortcutRecordingError = TestError.shortcutRestore
        let viewController = WorkspaceSettingsViewController(service: service)
        let workspacePill = try XCTUnwrap(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.1"
        })
        workspacePill.mouseUp(with: mouseEvent(type: .leftMouseUp))
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

    func testWorkspaceIDPickerDistinguishesConfiguredAndAvailableSelections() throws {
        let picker = WorkspaceIDPickerView(unavailableWorkspaceIDs: ["1", "A"])
        var availableSelection: WorkspaceID?
        var configuredSelection: WorkspaceID?
        picker.onWorkspaceSelected = { availableSelection = $0 }
        picker.onConfiguredWorkspaceSelected = { configuredSelection = $0 }
        let buttons = descendants(of: picker).compactMap { $0 as? WorkspaceIDKeyButton }
        let zero = try XCTUnwrap(buttons.first { $0.workspaceID == "0" })
        let one = try XCTUnwrap(buttons.first { $0.workspaceID == "1" })
        let letterA = try XCTUnwrap(buttons.first { $0.workspaceID == "A" })
        let letterB = try XCTUnwrap(buttons.first { $0.workspaceID == "B" })

        XCTAssertTrue(zero.isEnabled)
        XCTAssertTrue(one.isEnabled)
        XCTAssertTrue(letterA.isEnabled)

        letterA.performClick(nil)
        zero.performClick(nil)
        letterB.performClick(nil)

        XCTAssertEqual(configuredSelection, "A")
        XCTAssertEqual(availableSelection, "B")
    }

    func testWorkspaceIDPickerCentersTheKeyboard() {
        let picker = WorkspaceIDPickerView(unavailableWorkspaceIDs: [])
        picker.frame = NSRect(x: 0, y: 0, width: 520, height: 184)
        picker.layoutSubtreeIfNeeded()

        let buttons = descendants(of: picker).compactMap { $0 as? WorkspaceIDKeyButton }
        let frames = buttons.map { picker.convert($0.bounds, from: $0) }
        let keyboardFrame = frames.reduce(NSRect.null) { $0.union($1) }

        XCTAssertEqual(keyboardFrame.midX, picker.bounds.midX, accuracy: 1)
    }

    func testShortcutConflictsStayOnRecorderControlsWithoutASeparateSection() {
        let base = settingsSnapshot()
        let snapshot = WorkspaceSettingsSnapshot(
            config: KkaciConfig(workspaces: [WorkspaceConfig(id: "1")]),
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
                .switchWorkspace("1"): "Already assigned to \"Cycle Workspace · Next\"."
            ]
        )
        let viewController = WorkspaceSettingsViewController(
            service: WorkspaceSettingsServiceStub(snapshot: snapshot)
        )

        XCTAssertNil(descendants(of: viewController.view).first {
            $0.accessibilityIdentifier() == "kkaci.settings.shortcut-conflicts"
        })
    }

    func testWorkspaceDragPayloadRoundTripsWorkspaceID() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("kkaci.workspace-test"))
        pasteboard.clearContents()
        pasteboard.writeObjects([WorkspaceDragPayload.pasteboardItem(for: "A")])

        XCTAssertEqual(WorkspaceDragPayload.workspaceID(from: pasteboard), "A")
    }

    func testDisplayArrangementHitTestsTheWorkspaceUnderThePointer() throws {
        let display = WorkspaceSettingsDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            workspaceIDs: ["1", "Y"]
        )
        let arrangement = WorkspaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 520, height: 210))
        arrangement.apply(
            [display],
            selectedDisplayID: nil,
            selectedWorkspaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let one = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.1"
        })
        let letterY = try XCTUnwrap(descendants(of: arrangement).first {
            $0.accessibilityIdentifier() == "kkaci.settings.workspace-pill.Y"
        })
        let onePoint = NSPoint(x: one.frame.midX, y: one.frame.midY)
        let letterYPoint = NSPoint(x: letterY.frame.midX, y: letterY.frame.midY)

        XCTAssertTrue(one.hitTest(onePoint) === one)
        XCTAssertTrue(letterY.hitTest(letterYPoint) === letterY)
        XCTAssertNil(one.hitTest(letterYPoint))
        XCTAssertNil(letterY.hitTest(onePoint))
    }

    func testDisplayArrangementShowsOverflowInsteadOfDroppingWorkspaceIDs() throws {
        let display = WorkspaceSettingsDisplay(
            id: 1,
            name: "Small Display",
            frame: CGRect(x: 0, y: 0, width: 1000, height: 800),
            role: .main,
            monitorSlot: 1,
            workspaceIDs: WorkspaceID.allCases
        )
        let arrangement = WorkspaceDisplayArrangementView(frame: NSRect(x: 0, y: 0, width: 260, height: 140))
        arrangement.apply(
            [display],
            selectedDisplayID: 1,
            selectedWorkspaceID: nil,
            isEditable: true
        )
        arrangement.layoutSubtreeIfNeeded()

        let overflow = try XCTUnwrap(
            descendants(of: arrangement)
                .compactMap { $0 as? NSButton }
                .first { $0.accessibilityIdentifier() == "kkaci.settings.workspace-overflow" }
        )
        XCTAssertFalse(overflow.isHidden)
        XCTAssertTrue(overflow.title.hasPrefix("+"))
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
    workspaces: [WorkspaceConfig] = [WorkspaceConfig(id: "1")],
    workspaceWindowCounts: [WorkspaceID: Int] = [:]
) -> WorkspaceSettingsSnapshot {
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
        config: KkaciConfig(workspaces: workspaces),
        monitorSlots: [
            MonitorSlotSnapshot(slot: 1, display: main),
            MonitorSlotSnapshot(slot: 2, display: extended)
        ],
        workspaceWindowCounts: workspaceWindowCounts
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

private final class WorkspaceSettingsServiceStub: WorkspaceSettingsServing {
    let currentSnapshot: WorkspaceSettingsSnapshot
    var onUpdateMonitor: (WorkspaceID, DisplayID) throws -> Void = { _, _ in }
    var onAddWorkspaces: ([WorkspaceID], DisplayID) throws -> Void = { _, _ in }
    var onRemoveWorkspace: (WorkspaceID) throws -> Void = { _ in }
    var cancelShortcutRecordingError: Error?

    init(snapshot: WorkspaceSettingsSnapshot) {
        currentSnapshot = snapshot
    }

    func snapshot() -> WorkspaceSettingsSnapshot {
        currentSnapshot
    }

    func updateShortcut(_: String?, for _: ShortcutTarget) throws -> Bool {
        false
    }

    func updateMonitor(_ workspaceID: WorkspaceID, displayID: DisplayID) throws {
        try onUpdateMonitor(workspaceID, displayID)
    }

    func addWorkspaces(_ workspaceIDs: [WorkspaceID], displayID: DisplayID) throws {
        try onAddWorkspaces(workspaceIDs, displayID)
    }

    func removeWorkspace(_ workspaceID: WorkspaceID) throws {
        try onRemoveWorkspace(workspaceID)
    }

    func beginShortcutRecording() throws {}

    func cancelShortcutRecording() throws {
        if let cancelShortcutRecordingError {
            throw cancelShortcutRecordingError
        }
    }

    func shortcutRecordingDidFinish(didPersistChange _: Bool) {}
}

private final class WorkspaceSettingsShortcutInstaller: KeyboardShortcutInstalling {
    private(set) var replacedKeys: [[String]] = []

    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws {
        _ = try KeyboardShortcutResolver().resolve(registrations)
        replacedKeys.append(registrations.map(\.key))
    }
}
