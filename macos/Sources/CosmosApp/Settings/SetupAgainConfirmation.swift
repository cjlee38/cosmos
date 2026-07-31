import AppKit

func presentSetupAgainConfirmation(
    for window: NSWindow?,
    onConfirm: @escaping () -> Void
) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Restart Cosmos and Run Setup Again?"
    alert.informativeText = [
        "Cosmos will restart and attempt to restore its hidden windows before quitting.",
        "Any remaining windows will be recovered after setup is complete."
    ].joined(separator: " ")
    alert.addButton(withTitle: "Restart and Run Setup")
    alert.addButton(withTitle: "Cancel")
    alert.buttons.first?.hasDestructiveAction = true

    guard let window else {
        if alert.runModal() == .alertFirstButtonReturn {
            onConfirm()
        }
        return
    }

    alert.beginSheetModal(for: window) { response in
        guard response == .alertFirstButtonReturn else {
            return
        }
        onConfirm()
    }
}
