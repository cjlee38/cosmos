import Dispatch
import Foundation

public enum PanicRecovery {
    private static let lock = NSLock()
    private static var recovery: (() -> Void)?

    public static func install(_ recovery: @escaping () -> Void) {
        lock.lock()
        self.recovery = recovery
        lock.unlock()
    }

    static func perform(
        offMainTimeout: DispatchTimeInterval = .seconds(5)
    ) {
        lock.lock()
        let recovery = recovery
        lock.unlock()

        guard let recovery else {
            return
        }
        if Thread.isMainThread {
            recovery()
        } else {
            let completed = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                recovery()
                completed.signal()
            }
            _ = completed.wait(timeout: .now() + offMainTimeout)
        }
    }
}

public func panic(
    _ message: @autoclosure () -> String,
    file: StaticString = #fileID,
    line: UInt = #line
) -> Never {
    PanicRecovery.perform()
    Swift.fatalError(message(), file: file, line: line)
}
