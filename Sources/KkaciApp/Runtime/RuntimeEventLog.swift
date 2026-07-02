import Foundation

final class RuntimeEventLog {
    private(set) var entries: [RuntimeEvent] = [
        RuntimeEvent(message: "Ready")
    ]
    var onChange: (() -> Void)?

    var latestMessage: String {
        entries.last?.message ?? "Ready"
    }

    func record(_ message: String) {
        entries.append(RuntimeEvent(message: message))
        if entries.count > 100 {
            entries.removeFirst(entries.count - 100)
        }
        NSLog("[kkaci runtime] %@", message)
        onChange?()
    }
}

struct RuntimeEvent {
    let timestamp: Date
    let message: String

    init(timestamp: Date = Date(), message: String) {
        self.timestamp = timestamp
        self.message = message
    }
}
