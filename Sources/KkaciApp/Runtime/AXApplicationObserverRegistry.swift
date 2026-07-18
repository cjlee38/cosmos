import AppKit
import ApplicationServices
import Foundation

final class AXApplicationObserverRegistry {
    private let onNotification: (AXUIElement, CFString) -> Void
    private var observersByPID: [pid_t: AXObserver] = [:]

    init(onNotification: @escaping (AXUIElement, CFString) -> Void) {
        self.onNotification = onNotification
    }

    deinit {
        stop()
    }

    func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard canObserve(app),
              observersByPID[pid] == nil
        else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let createError = AXObserverCreate(
            pid,
            { _, element, notification, context in
                guard let context else {
                    return
                }

                let registry = Unmanaged<AXApplicationObserverRegistry>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                registry.onNotification(element, notification)
            },
            &observer
        )

        guard createError == .success, let observer else {
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        var didRegisterAnyNotification = false
        for notification in Self.observedNotifications {
            let error = AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                context
            )
            didRegisterAnyNotification = didRegisterAnyNotification || error == .success
        }

        guard didRegisterAnyNotification else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observersByPID[pid] = observer
    }

    func canObserve(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid()
    }

    func removeObserver(for pid: pid_t) {
        guard let observer = observersByPID.removeValue(forKey: pid) else {
            return
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    func stop() {
        for observer in observersByPID.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observersByPID.removeAll()
    }

    private static let observedNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification
    ]
}
