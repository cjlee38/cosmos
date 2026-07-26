import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceSettingsViewTests: XCTestCase {
    func testLeavingOnboardingSpaceStepCancelsShortcutRecording() throws {
        let permissionService = GeneralSettingsService(
            launchAtLoginStatusProvider: { .disabled },
            setLaunchAtLoginHandler: { _ in },
            permissionStatusProvider: { _ in true },
            openPermissionSettingsHandler: { _ in },
            openLoginItemsSettingsHandler: {}
        )
        let spaceService = SpaceSettingsServiceStub(snapshot: settingsSnapshot())
        var cancelCount = 0
        var completeCount = 0
        let viewController = OnboardingViewController(
            permissionViewController: OnboardingPermissionViewController(service: permissionService),
            spaceViewController: SpaceSettingsViewController(service: spaceService),
            canComplete: { true },
            onLeaveSpaces: {
                cancelCount += 1
                return true
            },
            onComplete: {
                completeCount += 1
            }
        )
        let buttons = descendants(of: viewController.view).compactMap { $0 as? NSButton }
        let continueButton = try XCTUnwrap(buttons.first {
            $0.accessibilityIdentifier() == "cosmos.onboarding.continue"
        })
        let backButton = try XCTUnwrap(buttons.first {
            $0.accessibilityIdentifier() == "cosmos.onboarding.back"
        })

        continueButton.performClick(nil)
        backButton.performClick(nil)
        continueButton.performClick(nil)
        continueButton.performClick(nil)

        XCTAssertEqual(cancelCount, 2)
        XCTAssertEqual(completeCount, 1)
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
