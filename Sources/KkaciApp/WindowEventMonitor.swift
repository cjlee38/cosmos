import AppKit
import ApplicationServices
import Foundation

final class WindowEventMonitor {
    private struct ObservedApp {
        let appElement: AXUIElement
        let observer: AXObserver
    }

    private enum Callback {
        case focusedWindowChanged
        case windowSetChanged
    }

    private let onFocusedWindowChanged: () -> Void
    private let onWindowSetChanged: () -> Void
    private var observedApps: [pid_t: ObservedApp] = [:]
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var pendingCallbacks: Set<Callback> = []

    init(
        onFocusedWindowChanged: @escaping () -> Void,
        onWindowSetChanged: @escaping () -> Void
    ) {
        self.onFocusedWindowChanged = onFocusedWindowChanged
        self.onWindowSetChanged = onWindowSetChanged
    }

    deinit {
        stop()
    }

    func start() {
        guard workspaceObserverTokens.isEmpty else {
            return
        }

        observeRunningApplications()
        observeWorkspaceLifecycle()
    }

    func stop() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObserverTokens {
            notificationCenter.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()

        for observedApp in observedApps.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observedApp.observer),
                .defaultMode
            )
        }
        observedApps.removeAll()
    }

    private func observeRunningApplications() {
        for app in NSWorkspace.shared.runningApplications {
            observe(app)
        }
    }

    private func observeWorkspaceLifecycle() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        workspaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observe(app)
                self?.scheduleFocusSyncIfObservable(app)
            }
        })

        workspaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observe(app)
                self?.schedule(.windowSetChanged)
            }
        })

        workspaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.removeObserver(for: app.processIdentifier)
            self?.schedule(.windowSetChanged)
        })
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard isObservable(app),
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

                let monitor = Unmanaged<WindowEventMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.handleAXNotification(notification)
            },
            &observer
        )

        guard createError == .success, let observer else {
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        var didRegisterAnyNotification = false
        for notification in [
            kAXFocusedWindowChangedNotification,
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
        ] {
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

    private func scheduleFocusSyncIfObservable(_ app: NSRunningApplication) {
        if isObservable(app) {
            schedule(.focusedWindowChanged)
        }
    }

    private func isObservable(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid()
    }

    private func removeObserver(for pid: pid_t) {
        guard let observedApp = observedApps.removeValue(forKey: pid) else {
            return
        }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observedApp.observer),
            .defaultMode
        )
    }

    private func handleAXNotification(_ notification: CFString) {
        let name = notification as String
        if name == kAXFocusedWindowChangedNotification {
            schedule(.focusedWindowChanged)
        } else {
            schedule(.windowSetChanged)
        }
    }

    private func schedule(_ callback: Callback) {
        guard pendingCallbacks.insert(callback).inserted else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            pendingCallbacks.remove(callback)
            switch callback {
            case .focusedWindowChanged:
                onFocusedWindowChanged()
            case .windowSetChanged:
                onWindowSetChanged()
            }
        }
    }
}
