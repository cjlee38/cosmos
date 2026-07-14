@testable import KkaciApp
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
            onPress: { pressCount += 1 },
            onRelease: { releaseCount += 1 }
        )])

        keyboardHandler?(.hotKeyPressed(1))
        modifierHandler?(0)

        XCTAssertEqual(pressCount, 1)
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

    func replaceHotKeys(_ hotKeys: [Keystroke]) throws -> [String: UInt32] {
        Dictionary(uniqueKeysWithValues: hotKeys.enumerated().map { index, hotKey in
            (hotKey.description, UInt32(index + 1))
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
