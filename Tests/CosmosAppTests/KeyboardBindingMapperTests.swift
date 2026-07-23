@testable import CosmosApp
import CosmosCore
import XCTest

final class KeyboardBindingMapperTests: XCTestCase {
    func testWindowSwitcherMapsPressRepeatAndReleaseToActions() throws {
        let actions = KeyboardShortcutActionSpy()
        let registration = try XCTUnwrap(
            KeyboardBindingMapper().registrations(
                for: [ConfiguredShortcut(key: "option+tab", target: .windowSwitcher)],
                actions: actions
            ).first
        )

        registration.onPress()
        registration.onRepeat?()
        registration.onRelease?()

        XCTAssertEqual(registration.target, .windowSwitcher)
        XCTAssertEqual(actions.windowSteps.count, 2)
        XCTAssertEqual(actions.windowSteps[0].direction, .forward)
        XCTAssertTrue(actions.windowSteps[0].wraps)
        XCTAssertEqual(actions.windowSteps[1].direction, .forward)
        XCTAssertFalse(actions.windowSteps[1].wraps)
        XCTAssertEqual(actions.windowCommitCount, 1)
    }

    func testSpaceSwitcherMapsForwardStepAndReleaseToActions() throws {
        let actions = KeyboardShortcutActionSpy()
        let registration = try XCTUnwrap(
            KeyboardBindingMapper().registrations(
                for: [ConfiguredShortcut(key: "option+shift+tab", target: .spaceSwitcher)],
                actions: actions
            ).first
        )

        registration.onPress()
        registration.onRelease?()

        XCTAssertEqual(registration.target, .spaceSwitcher)
        XCTAssertEqual(actions.spaceSteps, [.forward])
        XCTAssertEqual(actions.spaceCommitCount, 1)
    }

    func testSpaceCommandsPassConfiguredSpaceToActions() {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+d", target: .switchSpace("D")),
                ConfiguredShortcut(key: "option+shift+o", target: .moveWindow("O"))
            ],
            actions: actions
        )

        registrations.forEach { $0.onPress() }

        XCTAssertEqual(registrations.map(\.target), [.switchSpace("D"), .moveWindow("O")])
        XCTAssertEqual(actions.switchedSpaces, ["D"])
        XCTAssertEqual(actions.movedSpaces, ["O"])
    }

    func testCenterWindowShortcutMapsPressToCenterAction() throws {
        let actions = KeyboardShortcutActionSpy()
        let registration = try XCTUnwrap(
            KeyboardBindingMapper().registrations(
                for: [ConfiguredShortcut(key: "option+command+c", target: .centerWindow)],
                actions: actions
            ).first
        )

        registration.onPress()

        XCTAssertEqual(registration.target, .centerWindow)
        XCTAssertEqual(actions.centerWindowCount, 1)
    }

    func testSpaceSwitchShortcutsCannotShareTheSameTerminalKey() {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+1", target: .switchSpace("1")),
                ConfiguredShortcut(key: "control+1", target: .switchSpace("2"))
            ],
            actions: actions
        )

        XCTAssertThrowsError(try KeyboardShortcutResolver().resolve(registrations)) { error in
            guard let validationError = error as? KeyboardShortcutValidationError else {
                return XCTFail("Expected KeyboardShortcutValidationError, got \(error)")
            }

            XCTAssertEqual(validationError.issues.count, 2)
            XCTAssertEqual(
                Set(validationError.issues.compactMap(\.target)),
                Set([ShortcutTarget.switchSpace("1"), .switchSpace("2")])
            )
            XCTAssertTrue(validationError.issues.allSatisfy {
                $0.message.contains("Space selection key is also assigned")
            })
        }
    }

    func testSpaceSwitchShortcutsWithDifferentTerminalKeysAreValid() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+1", target: .switchSpace("1")),
                ConfiguredShortcut(key: "control+2", target: .switchSpace("2"))
            ],
            actions: actions
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 2)
    }

    func testSpaceActionsWithAdditionalModifiersDoNotConflictWithSelectionKey() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+shift+tab", target: .spaceSwitcher),
                ConfiguredShortcut(key: "option+b", target: .switchSpace("B")),
                ConfiguredShortcut(key: "control+b", target: .moveWindow("C"))
            ],
            actions: actions
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 3)
    }

    func testSpaceTerminalKeyDoesNotConflictWithoutSwitcherHoldModifier() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+shift+tab", target: .spaceSwitcher),
                ConfiguredShortcut(key: "option+b", target: .switchSpace("B")),
                ConfiguredShortcut(key: "option+shift+b", target: .moveWindow("C"))
            ],
            actions: actions
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 3)
    }

    func testCycleShortcutConflictMarksOnlyTheExactDuplicateActions() {
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+1", target: .spaceSwitcher),
                ConfiguredShortcut(key: "option+1", target: .switchSpace("1")),
                ConfiguredShortcut(key: "option+shift+1", target: .moveWindow("1")),
                ConfiguredShortcut(key: "option+2", target: .switchSpace("2")),
                ConfiguredShortcut(key: "option+shift+2", target: .moveWindow("2"))
            ],
            actions: KeyboardShortcutActionSpy()
        )

        XCTAssertThrowsError(try KeyboardShortcutResolver().resolve(registrations)) { error in
            guard let validationError = error as? KeyboardShortcutValidationError else {
                return XCTFail("Expected KeyboardShortcutValidationError, got \(error)")
            }
            XCTAssertEqual(
                Set(validationError.issues.compactMap(\.target)),
                Set([ShortcutTarget.spaceSwitcher, .switchSpace("1")])
            )
        }
    }
}

private final class KeyboardShortcutActionSpy: KeyboardShortcutActionHandling {
    struct WindowStep {
        let direction: SwitcherDirection
        let wraps: Bool
    }

    var spaceSteps: [SwitcherDirection] = []
    var spaceCommitCount = 0
    var windowSteps: [WindowStep] = []
    var windowCommitCount = 0
    var switchedSpaces: [SpaceID] = []
    var movedSpaces: [SpaceID] = []
    var centerWindowCount = 0

    func stepSpaceSwitcher(direction: SwitcherDirection) {
        spaceSteps.append(direction)
    }

    func commitSpaceSwitcher() {
        spaceCommitCount += 1
    }

    func stepWindowSwitcher(direction: SwitcherDirection, wraps: Bool) {
        windowSteps.append(WindowStep(direction: direction, wraps: wraps))
    }

    func commitWindowSwitcher() {
        windowCommitCount += 1
    }

    func cancelSwitcher() {}

    func switchSpace(to space: SpaceID) {
        switchedSpaces.append(space)
    }

    func moveFocusedWindow(to space: SpaceID) {
        movedSpaces.append(space)
    }

    func centerFocusedWindow() {
        centerWindowCount += 1
    }
}
