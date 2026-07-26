@testable import CosmosApp
import CosmosCore
import XCTest

final class SwitcherInteractionPolicyTests: XCTestCase {
    func testSpaceShortcutBindingsUseTheNonModifierKey() {
        let shortcuts = SpaceShortcutBindings([
            ConfiguredShortcut(key: "option+1", target: .switchSpace("1")),
            ConfiguredShortcut(key: "option+b", target: .switchSpace("B")),
            ConfiguredShortcut(key: "option+shift+c", target: .moveWindow("C"))
        ])

        XCTAssertEqual(shortcuts.key(for: "1"), "1")
        XCTAssertEqual(shortcuts.key(for: "B"), "b")
        XCTAssertEqual(shortcuts.spaceID(for: "B"), "B")
        XCTAssertNil(shortcuts.spaceID(for: "c"))
    }

    func testHoverGateResetsAtTheCurrentPointerLocation() {
        var pointerLocation = NSPoint(x: 10, y: 20)
        let gate = SwitcherHoverGate(pointerLocation: { pointerLocation })

        XCTAssertFalse(gate.allowHoverIfPointerMoved())
        pointerLocation.x += 1
        XCTAssertTrue(gate.allowHoverIfPointerMoved())

        gate.reset()
        XCTAssertFalse(gate.allowHoverIfPointerMoved())
        pointerLocation.y += 1
        XCTAssertTrue(gate.allowHoverIfPointerMoved())
    }

    func testOutsideClickDecisionUsesTheProvidedEventLocation() {
        let overlayFrame = CGRect(x: 100, y: 100, width: 200, height: 100)

        XCTAssertFalse(SwitcherOutsideClickMonitor.isOutsideClick(
            at: CGPoint(x: 150, y: 150),
            overlayFrame: overlayFrame
        ))
        XCTAssertTrue(SwitcherOutsideClickMonitor.isOutsideClick(
            at: CGPoint(x: 50, y: 150),
            overlayFrame: overlayFrame
        ))
    }
}
