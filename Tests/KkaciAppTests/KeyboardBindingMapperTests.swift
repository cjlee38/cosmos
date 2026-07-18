@testable import KkaciApp
import KkaciCore
import XCTest

final class KeyboardBindingMapperTests: XCTestCase {
    func testWindowSwitcherMapsPressRepeatAndReleaseToActions() throws {
        let actions = KeyboardShortcutActionSpy()
        let registration = try XCTUnwrap(
            KeyboardBindingMapper().registrations(
                for: [HotKeyBinding(key: "option+tab", command: "next-window")],
                actions: actions
            ).first
        )

        registration.onPress()
        registration.onRepeat?()
        registration.onRelease?()

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
                for: [HotKeyBinding(key: "ctrl+shift+tab", command: "previous-workspace")],
                actions: actions
            ).first
        )

        registration.onPress()
        registration.onRelease?()

        XCTAssertEqual(actions.workspaceSteps, [.backward])
        XCTAssertEqual(actions.workspaceCommitCount, 1)
    }

    func testWorkspaceCommandsPassConfiguredWorkspaceToActions() throws {
        let actions = KeyboardShortcutActionSpy()
        let registrations = try KeyboardBindingMapper().registrations(
            for: [
                HotKeyBinding(key: "option+d", command: "workspace", workspace: "D"),
                HotKeyBinding(key: "option+shift+o", command: "move-window-to-workspace", workspace: "O")
            ],
            actions: actions
        )

        registrations.forEach { $0.onPress() }

        XCTAssertEqual(actions.switchedWorkspaces, ["D"])
        XCTAssertEqual(actions.movedWorkspaces, ["O"])
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
    var switchedWorkspaces: [String] = []
    var movedWorkspaces: [String] = []

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

    func switchWorkspace(named workspace: String) {
        switchedWorkspaces.append(workspace)
    }

    func moveFocusedWindow(to workspace: String) {
        movedWorkspaces.append(workspace)
    }
}
