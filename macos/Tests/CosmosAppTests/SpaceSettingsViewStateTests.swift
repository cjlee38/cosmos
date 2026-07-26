import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceSettingsViewStateTests: XCTestCase {
    private enum TestError: Error {
        case shortcutRestore
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
