import AppKit
@testable import CosmosApp
import CosmosCore
import XCTest

final class AppearanceSettingsTests: XCTestCase {
    func testDefaultsUseAngleBracketsAndDefaultSwitcherSizes() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let snapshot = AppSettingsStore(defaults: defaults).snapshot()

        XCTAssertEqual(snapshot.menuBarIconStyle, .angleBrackets)
        XCTAssertEqual(snapshot.windowSwitcherSize, 1.75)
        XCTAssertEqual(snapshot.spaceSwitcherSize, 0.5)
    }

    func testAppearanceValuesPersistInUserDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)

        store.setMenuBarIconStyle(.squareBrackets)
        store.setWindowSwitcherSize(2.3)
        store.setSpaceSwitcherSize(0.2)

        let persisted = AppSettingsStore(defaults: defaults).snapshot()
        XCTAssertEqual(persisted.menuBarIconStyle, .squareBrackets)
        XCTAssertEqual(persisted.windowSwitcherSize, 2.3)
        XCTAssertEqual(persisted.spaceSwitcherSize, 0.2)
    }

    func testObsoletePresetValuesAreRemoved() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("large", forKey: "appearance.windowSwitcherItemSize")
        defaults.set("small", forKey: "appearance.spaceSwitcherItemSize")

        _ = AppSettingsStore(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "appearance.windowSwitcherItemSize"))
        XCTAssertNil(defaults.object(forKey: "appearance.spaceSwitcherItemSize"))
    }

    func testMenuBarTitleFormatterMarksTheCurrentSpace() {
        XCTAssertEqual(
            MenuBarTitleFormatter.title(
                spaces: ["1", "a"],
                currentSpace: "1",
                style: .angleBrackets
            ),
            "<•1 | a>"
        )
        XCTAssertEqual(
            MenuBarTitleFormatter.title(
                spaces: ["1", "a"],
                currentSpace: "a",
                style: .squareBrackets
            ),
            "[1 | •a]"
        )
    }

    func testSwitcherSizesIncreaseAcrossSliderRange() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)
        let factory = SwitcherOverlayContentController(appSettingsStore: store)
        let availableFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)

        store.setWindowSwitcherSize(1.0)
        let minimumWindow = windowListSize(factory: factory, availableFrame: availableFrame)
        store.setWindowSwitcherSize(1.75)
        let middleWindow = windowListSize(factory: factory, availableFrame: availableFrame)
        store.setWindowSwitcherSize(2.5)
        let maximumWindow = windowListSize(factory: factory, availableFrame: availableFrame)

        XCTAssertLessThan(minimumWindow.width, middleWindow.width)
        XCTAssertLessThan(middleWindow.width, maximumWindow.width)
        XCTAssertLessThan(minimumWindow.height, middleWindow.height)
        XCTAssertLessThan(middleWindow.height, maximumWindow.height)
        XCTAssertGreaterThan(middleWindow.width / minimumWindow.width, 1.2)
        XCTAssertGreaterThan(maximumWindow.width / middleWindow.width, 1.2)

        store.setSpaceSwitcherSize(0)
        let minimumSpace = spaceListSize(factory: factory, availableFrame: availableFrame)
        store.setSpaceSwitcherSize(0.5)
        let middleSpace = spaceListSize(factory: factory, availableFrame: availableFrame)
        store.setSpaceSwitcherSize(1)
        let maximumSpace = spaceListSize(factory: factory, availableFrame: availableFrame)

        XCTAssertLessThan(minimumSpace.width, middleSpace.width)
        XCTAssertLessThan(middleSpace.width, maximumSpace.width)
        XCTAssertLessThan(minimumSpace.height, middleSpace.height)
        XCTAssertLessThan(middleSpace.height, maximumSpace.height)
        XCTAssertGreaterThan(middleSpace.width / minimumSpace.width, 1.2)
        XCTAssertGreaterThan(maximumSpace.width / middleSpace.width, 1.2)
    }

    func testWindowSwitcherSliderResizesActualTileAndPreview() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppSettingsStore(defaults: defaults)
        let factory = SwitcherOverlayContentController(appSettingsStore: store)
        let availableFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let items = (1 ... 1).map { index in
            WindowSwitcherItem(
                windowID: WindowID(index),
                appName: "App \(index)",
                title: "Window \(index)",
                frame: nil,
                preview: NSImage(size: NSSize(width: 320, height: 180)),
                icon: nil
            )
        }

        let minimum = try windowTileAndPreviewSizes(
            size: 1.0,
            store: store,
            factory: factory,
            items: items,
            availableFrame: availableFrame
        )
        let middle = try windowTileAndPreviewSizes(
            size: 1.75,
            store: store,
            factory: factory,
            items: items,
            availableFrame: availableFrame
        )
        let maximum = try windowTileAndPreviewSizes(
            size: 2.5,
            store: store,
            factory: factory,
            items: items,
            availableFrame: availableFrame
        )

        XCTAssertLessThan(minimum.tile.width, middle.tile.width)
        XCTAssertLessThan(middle.tile.width, maximum.tile.width)
        XCTAssertLessThan(minimum.preview.height, middle.preview.height)
        XCTAssertLessThan(middle.preview.height, maximum.preview.height)
        XCTAssertGreaterThan(middle.preview.height / minimum.preview.height, 1.2)
        XCTAssertGreaterThan(maximum.preview.height / middle.preview.height, 1.2)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AppearanceSettingsTests.\(UUID().uuidString)"
        return try (XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }

    private func windowListSize(
        factory: SwitcherOverlayContentController,
        availableFrame: NSRect
    ) -> NSSize {
        factory.configureWindowList(
            items: [],
            selectedID: 0,
            availableFrame: availableFrame
        ).frame.size
    }

    private func spaceListSize(
        factory: SwitcherOverlayContentController,
        availableFrame: NSRect
    ) -> NSSize {
        factory.configureSpaceList(
            groups: [],
            selectedID: "",
            availableFrame: availableFrame,
            onHover: { _ in },
            onClick: { _ in }
        ).frame.size
    }

    private func windowTileAndPreviewSizes(
        size: Double,
        store: AppSettingsStore,
        factory: SwitcherOverlayContentController,
        items: [WindowSwitcherItem],
        availableFrame: NSRect
    ) throws -> (tile: NSSize, preview: NSSize) {
        store.setWindowSwitcherSize(size)
        let list = factory.configureWindowList(
            items: items,
            selectedID: items[0].windowID,
            availableFrame: availableFrame
        )
        let tile = try XCTUnwrap(list.subviews.compactMap { $0 as? WindowSwitcherTileView }.first)
        let preview = try XCTUnwrap(tile.subviews.max {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        })
        return (tile.frame.size, preview.frame.size)
    }
}
