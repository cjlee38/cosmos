import AppKit
import ApplicationServices
import Foundation

final class FocusedWindowMonitor {
    private struct ObservedApp {
        let appElement: AXUIElement
        let observer: AXObserver
    }

    private let onFocusedWindowChanged: () -> Void
    private var observedApps: [pid_t: ObservedApp] = [:]
    private var workspaceObserverTokens: [NSObjectProtocol] = []

    init(onFocusedWindowChanged: @escaping () -> Void) {
        self.onFocusedWindowChanged = onFocusedWindowChanged
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
            }
        })

        workspaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.observe(app)
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
        })
    }

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular,
              pid != getpid(),
              observedApps[pid] == nil
        else {
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let createError = AXObserverCreate(
            pid,
            { _, _, _, context in
                guard let context else {
                    return
                }

                let monitor = Unmanaged<FocusedWindowMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                monitor.onFocusedWindowChanged()
            },
            &observer
        )

        guard createError == .success, let observer else {
            return
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let addError = AXObserverAddNotification(
            observer,
            appElement,
            kAXFocusedWindowChangedNotification as CFString,
            context
        )

        guard addError == .success else {
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observedApps[pid] = ObservedApp(appElement: appElement, observer: observer)
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
}
