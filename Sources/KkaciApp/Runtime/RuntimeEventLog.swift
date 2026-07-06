import Foundation

final class RuntimeEventLog {
    private var messages = ["Ready"]
    var onChange: (() -> Void)?

    var latestMessage: String {
        messages.last ?? "Ready"
    }

    func record(_ message: String) {
        messages.append(message)
        if messages.count > 100 {
            messages.removeFirst(messages.count - 100)
        }
        NSLog("[kkaci runtime] %@", message)
        onChange?()
    }
}
