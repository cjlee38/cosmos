import CoreGraphics
import CosmosCore
import Foundation

final class DisplayReconfigurationMonitor {
    private let log = Log(category: "window-events")
    private let onBegin: () -> Void
    private let onAfter: () -> Void
    private var isRegistered = false

    init(
        onBegin: @escaping () -> Void,
        onAfter: @escaping () -> Void
    ) {
        self.onBegin = onBegin
        self.onAfter = onAfter
    }

    deinit {
        stop()
    }

    func start() {
        guard !isRegistered else {
            return
        }
        let status = CGDisplayRegisterReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard status == .success else {
            log.error("cg-register failed status=\(status.rawValue)")
            return
        }
        isRegistered = true
    }

    func stop() {
        guard isRegistered else {
            return
        }
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        isRegistered = false
    }

    fileprivate func receive(
        displayID _: DisplayID,
        flags: CGDisplayChangeSummaryFlags
    ) {
        let action = { [self] in
            if flags.contains(.beginConfigurationFlag) {
                onBegin()
            } else {
                onAfter()
            }
        }
        if Thread.isMainThread {
            action()
        } else {
            DispatchQueue.main.sync(execute: action)
        }
    }
}

private let displayReconfigurationCallback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
    guard let userInfo else {
        return
    }
    Unmanaged<DisplayReconfigurationMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .receive(displayID: displayID, flags: flags)
}
