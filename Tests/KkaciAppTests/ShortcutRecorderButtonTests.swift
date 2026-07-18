import AppKit
import Carbon
@testable import KkaciApp
import KkaciCore
import XCTest

final class ShortcutRecorderButtonTests: XCTestCase {
    func testValidationMessageShowsWarningIconWithoutReplacingShortcut() {
        let message = "Already assigned to \"Switch to Workspace 2\"."
        let button = ShortcutRecorderButton(
            shortcutTarget: .switchWorkspace("1"),
            shortcut: "option+1",
            validationMessage: message
        )
        let control = ShortcutRecorderControl(
            recorderButton: button,
            validationMessage: message
        )

        XCTAssertEqual(button.title, "⌥ 1")
        XCTAssertEqual(button.toolTip, message)
        XCTAssertTrue(button.isBordered)
        XCTAssertEqual(button.bezelStyle, .rounded)
        XCTAssertEqual(control.warningIcon.alphaValue, 1)
        XCTAssertEqual(control.warningIcon.toolTip, message)

        XCTAssertTrue(button.startRecording(onCommit: { _ in }, onCancel: {}, onFinish: {}))
        XCTAssertEqual(control.warningIcon.alphaValue, 0)

        button.cancelRecording()
        XCTAssertEqual(control.warningIcon.alphaValue, 1)
        XCTAssertEqual(button.toolTip, message)
        XCTAssertEqual(control.warningIcon.toolTip, message)
    }

    func testControlWithoutValidationReservesHiddenWarningIconSpace() {
        let button = ShortcutRecorderButton(
            shortcutTarget: .switchWorkspace("1"),
            shortcut: "option+1"
        )
        let control = ShortcutRecorderControl(
            recorderButton: button,
            validationMessage: nil
        )

        XCTAssertNil(button.toolTip)
        XCTAssertFalse(control.warningIcon.isHidden)
        XCTAssertEqual(control.warningIcon.alphaValue, 0)
        XCTAssertNil(control.warningIcon.toolTip)
    }

    func testRecorderCommitsCanonicalShortcutAndDeleteClearsIt() throws {
        let button = ShortcutRecorderButton(shortcutTarget: .switchWorkspace("1"), shortcut: "option+1")
        var committed: [String?] = []
        XCTAssertTrue(button.startRecording(
            onCommit: { committed.append($0) },
            onCancel: {},
            onFinish: {}
        ))
        XCTAssertEqual(button.attributedTitle.string, "●  REC")

        try button.keyDown(with: keyEvent(keyCode: kVK_ANSI_A, modifiers: [.option, .shift]))

        XCTAssertEqual(committed.count, 1)
        XCTAssertEqual(committed[0], "option+shift+a")
        XCTAssertEqual(button.currentShortcut, "option+shift+a")
        XCTAssertEqual(button.title, "⌥ ⇧ A")
        XCTAssertFalse(button.isRecording)

        XCTAssertTrue(button.startRecording(
            onCommit: { committed.append($0) },
            onCancel: {},
            onFinish: {}
        ))
        try button.keyDown(with: keyEvent(keyCode: kVK_Delete))

        XCTAssertEqual(committed.count, 2)
        XCTAssertNil(committed[1])
        XCTAssertNil(button.currentShortcut)
    }

    private func keyEvent(
        keyCode: Int,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        ))
    }
}
