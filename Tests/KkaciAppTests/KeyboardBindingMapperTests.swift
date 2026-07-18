@testable import KkaciApp
import KkaciCore
import XCTest

final class KeyboardBindingMapperTests: XCTestCase {
    func testWindowSwitcherMapsPressRepeatAndReleaseToActions() throws {
        let actions = KeyboardShortcutActionSpy()
        let registration = try XCTUnwrap(
            KeyboardBindingMapper().registrations(
                for: [ConfiguredShortcut(key: "option+tab", target: .windowSwitcherNext)],
                actions: actions
            ).first
        )

        registration.onPress()
        registration.onRepeat?()
        registration.onRelease?()

        XCTAssertEqual(registration.target, .windowSwitcherNext)
        XCTAssertEqual(actions.windowSteps.count, 2)
        XCTAssertEqual(actions.windowSteps[0].direction, .forward)
        XCTAssertTrue(actions.windowSteps[0].wraps)
        XCTAssertEqual(actions.windowSteps[1].direction, .forward)
        XCTAssertFalse(actions.windowSteps[1].wraps)
        XCTAssertEqual(actions.windowCommitCount, 1)
    }

    func testWorkspaceSwitcherMapsDirectionAndReleaseToActions() throws {
        let actions = KeyboardShortcutActionSpy()
        let registration = try XCTUnwrap(
            KeyboardBindingMapper().registrations(
                for: [ConfiguredShortcut(key: "ctrl+shift+tab", target: .workspaceSwitcherPrevious)],
                actions: actions
            ).first
        )

        registration.onPress()
        registration.onRelease?()

        XCTAssertEqual(registration.target, .workspaceSwitcherPrevious)
        XCTAssertEqual(actions.workspaceSteps, [.backward])
        XCTAssertEqual(actions.workspaceCommitCount, 1)
    }

    func testWorkspaceCommandsPassConfiguredWorkspaceToActions() {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+d", target: .switchWorkspace("D")),
                ConfiguredShortcut(key: "option+shift+o", target: .moveWindow("O"))
            ],
            actions: actions
        )

        registrations.forEach { $0.onPress() }

        XCTAssertEqual(registrations.map(\.target), [.switchWorkspace("D"), .moveWindow("O")])
        XCTAssertEqual(actions.switchedWorkspaces, ["D"])
        XCTAssertEqual(actions.movedWorkspaces, ["O"])
    }

    func testWorkspaceSwitchShortcutsCannotShareTheSameTerminalKey() {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+1", target: .switchWorkspace("1")),
                ConfiguredShortcut(key: "control+1", target: .switchWorkspace("2"))
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
                Set([ShortcutTarget.switchWorkspace("1"), .switchWorkspace("2")])
            )
            XCTAssertTrue(validationError.issues.allSatisfy {
                $0.message.contains("Workspace selection key is also assigned")
            })
        }
    }

    func testWorkspaceSwitchShortcutsWithDifferentTerminalKeysAreValid() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "option+1", target: .switchWorkspace("1")),
                ConfiguredShortcut(key: "control+2", target: .switchWorkspace("2"))
            ],
            actions: actions
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 2)
    }

    func testWorkspaceActionsWithAdditionalModifiersDoNotConflictWithSelectionKey() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "control+tab", target: .workspaceSwitcherNext),
                ConfiguredShortcut(key: "option+b", target: .switchWorkspace("B")),
                ConfiguredShortcut(key: "control+b", target: .moveWindow("C"))
            ],
            actions: actions
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 3)
    }

    func testWorkspaceTerminalKeyDoesNotConflictWithoutSwitcherHoldModifier() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "control+tab", target: .workspaceSwitcherNext),
                ConfiguredShortcut(key: "option+b", target: .switchWorkspace("B")),
                ConfiguredShortcut(key: "option+shift+b", target: .moveWindow("C"))
            ],
            actions: actions
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 3)
    }

    func testSwitcherDirectionsMayUseDifferentHoldModifiers() throws {
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "control+tab", target: .workspaceSwitcherNext),
                ConfiguredShortcut(key: "option+shift+tab", target: .workspaceSwitcherPrevious)
            ],
            actions: KeyboardShortcutActionSpy()
        )

        XCTAssertEqual(try KeyboardShortcutResolver().resolve(registrations).count, 2)
    }

    func testCycleShortcutConflictMarksOnlyTheExactDuplicateActions() {
        let registrations = KeyboardBindingMapper().registrations(
            for: [
                ConfiguredShortcut(key: "control+tab", target: .workspaceSwitcherNext),
                ConfiguredShortcut(key: "option+1", target: .workspaceSwitcherPrevious),
                ConfiguredShortcut(key: "option+1", target: .switchWorkspace("1")),
                ConfiguredShortcut(key: "option+shift+1", target: .moveWindow("1")),
                ConfiguredShortcut(key: "option+2", target: .switchWorkspace("2")),
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
                Set([ShortcutTarget.workspaceSwitcherPrevious, .switchWorkspace("1")])
            )
        }
    }
}

private final class KeyboardShortcutActionSpy: KeyboardShortcutActionHandling {
    struct WindowStep {
        let direction: SwitcherDirection
        let wraps: Bool
    }

    var workspaceSteps: [SwitcherDirection] = []
    var workspaceCommitCount = 0
    var windowSteps: [WindowStep] = []
    var windowCommitCount = 0
    var switchedWorkspaces: [WorkspaceID] = []
    var movedWorkspaces: [WorkspaceID] = []

    func stepWorkspaceSwitcher(direction: SwitcherDirection) {
        workspaceSteps.append(direction)
    }

    func commitWorkspaceSwitcher() {
        workspaceCommitCount += 1
    }

    func stepWindowSwitcher(direction: SwitcherDirection, wraps: Bool) {
        windowSteps.append(WindowStep(direction: direction, wraps: wraps))
    }

    func commitWindowSwitcher() {
        windowCommitCount += 1
    }

    func cancelSwitcher() {}

    func switchWorkspace(to workspace: WorkspaceID) {
        switchedWorkspaces.append(workspace)
    }

    func moveFocusedWindow(to workspace: WorkspaceID) {
        movedWorkspaces.append(workspace)
    }
}
