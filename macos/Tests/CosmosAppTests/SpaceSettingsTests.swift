import AppKit
import CoreGraphics
@testable import CosmosApp
import CosmosCore
import XCTest

final class SpaceSettingsServiceTests: XCTestCase {
    func testOnboardingSpaceEditDefersRuntimeChangesUntilInitialShortcutInstall() throws {
        let (controller, _) = try makeSwitcherTestController(windows: [])
        let initialConfig = controller.currentConfig
        let configStore = ConfigStoreSpy(loadedConfig: initialConfig)
        let shortcutInstaller = SpaceSettingsShortcutInstaller()
        let configRuntime = ConfigRuntime(
            configStore: configStore,
            configURL: nil,
            controller: controller,
            keyboardShortcutManager: shortcutInstaller,
            keyboardBindingMapper: KeyboardBindingMapper()
        )
        let actions = NoopShortcutActions()
        var runtimeMode = SpaceSettingsRuntimeMode.deferredUntilStartup
        let service = SpaceSettingsService(
            controller: controller,
            configRuntime: configRuntime,
            actions: actions,
            runtimeMode: { runtimeMode },
            refreshAfterChange: {}
        )

        try service.addSpaces(["A"], displayID: 1)

        let savedConfig = try XCTUnwrap(configStore.savedConfigs.last)
        XCTAssertTrue(savedConfig.spaces.map(\.id).contains("A"))
        XCTAssertEqual(controller.currentConfig, initialConfig)
        XCTAssertTrue(shortcutInstaller.replacedKeys.isEmpty)

        try configRuntime.installInitialShortcuts(actions: actions)

        XCTAssertEqual(controller.currentConfig, savedConfig)
        XCTAssertEqual(shortcutInstaller.replacedKeys, [savedConfig.configuredShortcuts.map(\.key)])

        runtimeMode = .active
        try service.addSpaces(["B"], displayID: 1)

        XCTAssertTrue(controller.currentConfig.spaces.map(\.id).contains("B"))
        XCTAssertEqual(shortcutInstaller.replacedKeys.count, 2)
    }

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

func mouseEvent(type: NSEvent.EventType) -> NSEvent {
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

func settingsSnapshot(
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

func snapshotConfig() -> CosmosConfig {
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

func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants)
}

final class SpaceSettingsServiceStub: SpaceSettingsServing {
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
