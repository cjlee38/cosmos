import AppKit
import ApplicationServices
import Foundation

final class WindowEventMonitor {
    private enum Callback {
        case focusedWindowChanged
        case windowSetChanged
    }

    private let onFocusedWindowChanged: () -> Void
    private let onWindowSetChanged: () -> Void
    private lazy var axObserverRegistry = AXApplicationObserverRegistry { [weak self] notification in
        self?.handleAXNotification(notification)
    }
    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var appObserverTokens: [NSObjectProtocol] = []
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
        observeDisplayChanges()
    }

    func stop() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for token in workspaceObserverTokens {
            notificationCenter.removeObserver(token)
        }
        workspaceObserverTokens.removeAll()

        for token in appObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        appObserverTokens.removeAll()

        axObserverRegistry.stop()
    }

    private func observeRunningApplications() {
        for app in NSWorkspace.shared.runningApplications {
            axObserverRegistry.observe(app)
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
                self?.axObserverRegistry.observe(app)
                self?.scheduleFocusSyncIfObservable(app)
            }
        })

        workspaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.axObserverRegistry.observe(app)
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
            self?.axObserverRegistry.removeObserver(for: app.processIdentifier)
            self?.schedule(.windowSetChanged)
        })
    }

    private func observeDisplayChanges() {
        appObserverTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedule(.windowSetChanged)
        })
    }

    private func scheduleFocusSyncIfObservable(_ app: NSRunningApplication) {
        if axObserverRegistry.canObserve(app) {
            schedule(.focusedWindowChanged)
        }
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
