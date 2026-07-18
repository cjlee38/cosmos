@testable import KkaciApp
import Carbon
import XCTest

final class KeyboardShortcutManagerTests: XCTestCase {
    func testPressAndModifierReleaseInvokeOneHoldSession() throws {
        let backend = CarbonKeyboardSpy()
        let modifierMonitor = ModifierFlagsMonitorSpy()
        var keyboardHandler: ((CarbonKeyboardEvent) -> Void)?
        var modifierHandler: ((UInt32) -> Void)?
        let manager = KeyboardShortcutManager(
            makeBackend: {
                keyboardHandler = $0
                return backend
            },
            makeModifierFlagsMonitor: {
                modifierHandler = $0
                return modifierMonitor
            }
        )
        var pressCount = 0
        var releaseCount = 0

        try manager.start()
        try manager.replaceShortcuts([.hold(
            key: "option+tab",
            name: "window-switcher",
            releaseGroup: "window-switcher",
            actions: .init(
                onPress: { pressCount += 1 },
                onRelease: { releaseCount += 1 },
                onCancel: {}
            )
        )])

        keyboardHandler?(.hotKeyPressed(1))
        modifierHandler?(0)

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(releaseCount, 1)
    }

    func testReplacingShortcutsCancelsActiveHoldWithoutCommittingOnLaterRelease() throws {
        let backend = CarbonKeyboardSpy()
        let modifierMonitor = ModifierFlagsMonitorSpy()
        var keyboardHandler: ((CarbonKeyboardEvent) -> Void)?
        var modifierHandler: ((UInt32) -> Void)?
        let manager = KeyboardShortcutManager(
            makeBackend: {
                keyboardHandler = $0
                return backend
            },
            makeModifierFlagsMonitor: {
                modifierHandler = $0
                return modifierMonitor
            }
        )
        var releaseCount = 0
        var cancelCount = 0

        try manager.start()
        try manager.replaceShortcuts([.hold(
            key: "option+tab",
            name: "window-switcher",
            releaseGroup: "window-switcher",
            actions: .init(
                onPress: {},
                onRelease: { releaseCount += 1 },
                onCancel: { cancelCount += 1 }
            )
        )])
        keyboardHandler?(.hotKeyPressed(1))

        try manager.replaceShortcuts([])
        modifierHandler?(0)

        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(releaseCount, 0)
    }

    func testHoldSessionUsesModifierOfShortcutThatStartedIt() throws {
        let harness = KeyboardManagerHarness(repeatController: ShortcutRepeatSpy())
        var releaseCount = 0
        try harness.manager.start()
        try harness.manager.replaceShortcuts([
            .hold(
                key: "control+tab",
                name: "next",
                releaseGroup: "workspace-switcher",
                actions: .init(
                    onPress: {},
                    onRelease: { releaseCount += 1 },
                    onCancel: {}
                )
            ),
            .hold(
                key: "option+shift+tab",
                name: "previous",
                releaseGroup: "workspace-switcher",
                actions: .init(
                    onPress: {},
                    onRelease: { releaseCount += 1 },
                    onCancel: {}
                )
            )
        ])

        harness.keyboardHandler?(.hotKeyPressed(2))
        harness.modifierHandler?(UInt32(optionKey))
        XCTAssertEqual(releaseCount, 0)

        harness.modifierHandler?(0)
        XCTAssertEqual(releaseCount, 1)
    }

    func testPartialStartFailureStopsBothInputsAndAllowsRetry() throws {
        let backend = CarbonKeyboardSpy()
        let modifierMonitor = ModifierFlagsMonitorSpy(startError: TestError.modifierStart)
        let manager = KeyboardShortcutManager(
            makeBackend: { _ in backend },
            makeModifierFlagsMonitor: { _ in modifierMonitor }
        )

        XCTAssertThrowsError(try manager.start()) { error in
            XCTAssertEqual(error as? TestError, .modifierStart)
        }
        XCTAssertEqual(backend.startCount, 1)
        XCTAssertEqual(backend.stopCount, 1)
        XCTAssertEqual(modifierMonitor.startCount, 1)
        XCTAssertEqual(modifierMonitor.stopCount, 1)

        modifierMonitor.startError = nil
        try manager.start()

        XCTAssertEqual(backend.startCount, 2)
        XCTAssertEqual(modifierMonitor.startCount, 2)
    }

    func testRepeatStartsAfterPressAndStopsOnKeyUp() throws {
        let repeatController = ShortcutRepeatSpy()
        let harness = KeyboardManagerHarness(repeatController: repeatController)
        var pressCount = 0
        var repeatCount = 0
        try harness.manager.start()
        try harness.manager.replaceShortcuts([.hold(
            key: "option+tab",
            name: "window-switcher",
            releaseGroup: "window-switcher",
            actions: .init(
                onPress: { pressCount += 1 },
                onRepeat: { repeatCount += 1 },
                onRelease: {},
                onCancel: {}
            )
        )])

        harness.keyboardHandler?(.hotKeyPressed(1))
        repeatController.fire()
        harness.keyboardHandler?(.hotKeyReleased(1))
        repeatController.fire()

        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(repeatCount, 1)
        XCTAssertEqual(repeatController.stopCount, 2)
    }

    func testModifierReleaseStopsRepeatAndCommitsHoldGroup() throws {
        let repeatController = ShortcutRepeatSpy()
        let harness = KeyboardManagerHarness(repeatController: repeatController)
        var releaseCount = 0
        try harness.manager.start()
        try harness.manager.replaceShortcuts([.hold(
            key: "option+tab",
            name: "window-switcher",
            releaseGroup: "window-switcher",
            actions: .init(
                onPress: {},
                onRepeat: {},
                onRelease: { releaseCount += 1 },
                onCancel: {}
            )
        )])

        harness.keyboardHandler?(.hotKeyPressed(1))
        harness.modifierHandler?(0)

        XCTAssertEqual(releaseCount, 1)
        XCTAssertNil(repeatController.action)
    }

    func testReplacingShortcutsStopsRepeatAndCancelsHoldGroup() throws {
        let repeatController = ShortcutRepeatSpy()
        let harness = KeyboardManagerHarness(repeatController: repeatController)
        var cancelCount = 0
        try harness.manager.start()
        try harness.manager.replaceShortcuts([.hold(
            key: "option+tab",
            name: "window-switcher",
            releaseGroup: "window-switcher",
            actions: .init(
                onPress: {},
                onRepeat: {},
                onRelease: {},
                onCancel: { cancelCount += 1 }
            )
        )])
        harness.keyboardHandler?(.hotKeyPressed(1))

        try harness.manager.replaceShortcuts([])

        XCTAssertEqual(cancelCount, 1)
        XCTAssertNil(repeatController.action)
    }
}

private enum TestError: Error, Equatable {
    case modifierStart
}

private final class CarbonKeyboardSpy: CarbonKeyboardHandling {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() throws {
        startCount += 1
    }

    func replaceHotKeys(_ hotKeys: [Keystroke]) throws -> [Keystroke: UInt32] {
        Dictionary(uniqueKeysWithValues: hotKeys.enumerated().map { index, hotKey in
            (hotKey, UInt32(index + 1))
        })
    }

    func stop() {
        stopCount += 1
    }
}

private final class ModifierFlagsMonitorSpy: ModifierFlagsMonitoring {
    var startError: Error?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(startError: Error? = nil) {
        self.startError = startError
    }

    func start() throws {
        startCount += 1
        if let startError {
            throw startError
        }
    }

    func stop() {
        stopCount += 1
    }
}

private final class ShortcutRepeatSpy: ShortcutRepeating {
    private(set) var action: (() -> Void)?
    private(set) var stopCount = 0

    func start(action: @escaping () -> Void) {
        self.action = action
    }

    func stop() {
        stopCount += 1
        action = nil
    }

    func fire() {
        action?()
    }
}

private final class KeyboardManagerHarness {
    private let handlers: KeyboardHandlerStore
    let manager: KeyboardShortcutManager

    var keyboardHandler: ((CarbonKeyboardEvent) -> Void)? {
        handlers.keyboard
    }

    var modifierHandler: ((UInt32) -> Void)? {
        handlers.modifiers
    }

    init(repeatController: any ShortcutRepeating) {
        let backend = CarbonKeyboardSpy()
        let modifierMonitor = ModifierFlagsMonitorSpy()
        let handlers = KeyboardHandlerStore()
        self.handlers = handlers
        manager = KeyboardShortcutManager(
            makeBackend: {
                handlers.keyboard = $0
                return backend
            },
            makeModifierFlagsMonitor: {
                handlers.modifiers = $0
                return modifierMonitor
            },
            repeatController: repeatController
        )
    }
}

private final class KeyboardHandlerStore {
    var keyboard: ((CarbonKeyboardEvent) -> Void)?
    var modifiers: ((UInt32) -> Void)?
}
