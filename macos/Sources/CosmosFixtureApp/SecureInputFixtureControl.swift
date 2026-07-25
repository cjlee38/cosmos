import AppKit
import Carbon

final class SecureInputFixtureControl: NSObject {
    private weak var statusLabel: NSTextField?
    private var isEnabled = false

    func makeView() -> NSView {
        let enableButton = makeButton(title: "Enable Secure Input", action: #selector(enable))
        let disableButton = makeButton(title: "Disable Secure Input", action: #selector(disableButtonPressed))
        let checkButton = makeButton(title: "Check Secure Input", action: #selector(check))

        let statusLabel = NSTextField(labelWithString: "UNKNOWN")
        statusLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        self.statusLabel = statusLabel

        let controls = NSStackView(views: [enableButton, disableButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 10

        let status = NSStackView(views: [checkButton, statusLabel])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 10

        let stack = NSStackView(views: [controls, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    func disable() {
        guard isEnabled else {
            check()
            return
        }
        if DisableSecureEventInput() == noErr {
            isEnabled = false
        }
        check()
    }

    @objc private func enable() {
        guard !isEnabled else {
            check()
            return
        }
        isEnabled = EnableSecureEventInput() == noErr
        check()
    }

    @objc private func disableButtonPressed() {
        disable()
    }

    @objc private func check() {
        statusLabel?.stringValue = IsSecureEventInputEnabled() ? "ON" : "OFF"
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }
}
