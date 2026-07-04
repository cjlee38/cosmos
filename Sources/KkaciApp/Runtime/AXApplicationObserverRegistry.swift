import AppKit
import ApplicationServices
import Foundation

final class AXApplicationObserverRegistry {
    private struct ObservedApp {
        let appElement: AXUIElement
        let observer: AXObserver
    }

    private let onNotification: (CFString) -> Void
    private var observedApps: [pid_t: ObservedApp] = [:]

    init(onNotification: @escaping (CFString) -> Void) {
        self.onNotification = onNotification
    }

    deinit {
        stop()
    }

    func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard canObserve(app),
              observedApps[pid] == nil
        else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let createError = AXObserverCreate(
            pid,
            { _, _, notification, context in
                guard let context else {
                    return
                }

                let registry = Unmanaged<AXApplicationObserverRegistry>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                registry.onNotification(notification)
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
        observedApps[pid] = ObservedApp(appElement: appElement, observer: observer)
    }

    func canObserve(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid()
    }

    func removeObserver(for pid: pid_t) {
        guard let observedApp = observedApps.removeValue(forKey: pid) else {
            return
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observedApp.observer),
            .defaultMode
        )
    }

    func stop() {
        for observedApp in observedApps.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observedApp.observer),
                .defaultMode
            )
        }
        observedApps.removeAll()
    }

    private static let observedNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]
}
