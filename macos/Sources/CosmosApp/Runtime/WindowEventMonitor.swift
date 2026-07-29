import AppKit
import ApplicationServices
import CoreGraphics
import CosmosCore
import Foundation

final class WindowEventMonitor {
    private let onEvents: (WindowRuntimeEventBatch) -> Void
    private let onSessionActivityChanged: (Bool) -> Void
    private let onSystemSleepChanged: (Bool) -> Void
    private lazy var axObserverRegistry = AXApplicationObserverRegistry { [weak self] element, notification in
        self?.handleAXNotification(element: element, notification: notification)
    }

    private var spaceObserverTokens: [NSObjectProtocol] = []
    private var appObserverTokens: [NSObjectProtocol] = []
    private var eventBuffer = WindowRuntimeEventBuffer()
    private var globalMouseUpMonitor: Any?
    private var localMouseUpMonitor: Any?

    init(
        onSessionActivityChanged: @escaping (Bool) -> Void = { _ in },
        onSystemSleepChanged: @escaping (Bool) -> Void = { _ in },
        onEvents: @escaping (WindowRuntimeEventBatch) -> Void
    ) {
        self.onSessionActivityChanged = onSessionActivityChanged
        self.onSystemSleepChanged = onSystemSleepChanged
        self.onEvents = onEvents
    }

    deinit {
        stop()
    }

    func start() {
        guard spaceObserverTokens.isEmpty else {
            return
        }

        observeRunningApplications()
        observeSpaceLifecycle()
        observeDisplayChanges()
    }

    func stop() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for token in spaceObserverTokens {
            notificationCenter.removeObserver(token)
        }
        spaceObserverTokens.removeAll()

        for token in appObserverTokens {
            NotificationCenter.default.removeObserver(token)
        }
        appObserverTokens.removeAll()

        axObserverRegistry.stop()
        stopMouseUpMonitor()
    }

    func scheduleOwnWindowChanged(_ windowID: WindowID) {
        if isLeftMouseButtonDown {
            startOwnWindowDragIfNeeded(windowID: windowID)
        }
        schedule(.init(kind: .layoutChanged, windowID: windowID))
        schedule(.init(kind: .thumbnailChanged, windowID: windowID))
    }

    private func observeRunningApplications() {
        for app in NSWorkspace.shared.runningApplications {
            axObserverRegistry.observe(app)
        }
    }

    private func observeSpaceLifecycle() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.axObserverRegistry.observe(app)
                self?.scheduleFocusSyncIfObservable(app)
            }
        })

        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.axObserverRegistry.observe(app)
                self?.schedule(.init(kind: .windowSetChanged, windowID: nil))
            }
        })

        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.axObserverRegistry.removeObserver(for: app.processIdentifier)
            self?.schedule(.init(
                kind: .applicationTerminated,
                windowID: nil,
                processID: app.processIdentifier
            ))
        })

        observeUserSessionLifecycle(notificationCenter)
        observeSystemSleepLifecycle(notificationCenter)
    }

    private func suspendForInactiveSession() {
        eventBuffer.suspend(.userSession)
        stopMouseUpMonitor()
        onSessionActivityChanged(false)
    }

    private func resumeAfterInactiveSession() {
        eventBuffer.resume(.userSession)
        onSessionActivityChanged(true)
        scheduleDelivery()
    }

    private func observeDisplayChanges() {
        appObserverTokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedule(.init(kind: .displayChanged, windowID: nil))
        })
    }

    private func scheduleFocusSyncIfObservable(_ app: NSRunningApplication) {
        if app.processIdentifier == getpid(), app.activationPolicy == .regular {
            schedule(.init(kind: .applicationActivated, windowID: nil))
            return
        }
        if axObserverRegistry.canObserve(app) {
            schedule(.init(kind: .applicationActivated, windowID: nil))
        }
    }

    private func handleAXNotification(element: AXUIElement, notification: CFString) {
        let notificationName = notification as String
        let kinds = WindowRuntimeEventKind.kinds(forAXNotification: notificationName)
        guard !kinds.isEmpty else {
            return
        }
        if notificationName == kAXFocusedWindowChangedNotification {
            var sourcePID: pid_t = 0
            AXUIElementGetPid(element, &sourcePID)
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            guard AXFocusChangeFilter.acceptsFocusChange(
                sourcePID: sourcePID,
                frontmostPID: frontmostPID
            ) else {
                return
            }
        }
        let windowID = AXClient.windowID(for: element)
        if isMouseDrivenLayoutNotification(notification),
           isLeftMouseButtonDown,
           let windowID {
            startExternalWindowDragIfNeeded(windowID: windowID)
        }
        for kind in kinds {
            schedule(.init(kind: kind, windowID: windowID))
        }
    }

    private func isMouseDrivenLayoutNotification(_ notification: CFString) -> Bool {
        notification as String == kAXWindowMovedNotification
            || notification as String == kAXWindowResizedNotification
    }

    private var isLeftMouseButtonDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    private func startExternalWindowDragIfNeeded(windowID: WindowID) {
        guard !eventBuffer.isWindowDragActive else {
            return
        }
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.finishWindowDrag()
        }) else {
            return
        }

        globalMouseUpMonitor = monitor
        eventBuffer.beginWindowDrag(windowID: windowID)
    }

    private func startOwnWindowDragIfNeeded(windowID: WindowID) {
        guard !eventBuffer.isWindowDragActive else {
            return
        }
        guard let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            self?.finishWindowDrag()
            return event
        }) else {
            return
        }

        localMouseUpMonitor = monitor
        eventBuffer.beginWindowDrag(windowID: windowID)
    }

    private func finishWindowDrag() {
        eventBuffer.endWindowDrag()
        stopMouseUpMonitor()
        scheduleDelivery()
    }

    private func stopMouseUpMonitor() {
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
            self.globalMouseUpMonitor = nil
        }
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
            self.localMouseUpMonitor = nil
        }
    }

    private func schedule(_ event: WindowRuntimeEvent) {
        eventBuffer.append(event)
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        guard eventBuffer.reserveDelivery() else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            guard let events = eventBuffer.takeDelivery() else {
                return
            }
            onEvents(WindowRuntimeEventBatch(events: events))
        }
    }
}

private extension WindowEventMonitor {
    func observeUserSessionLifecycle(_ notificationCenter: NotificationCenter) {
        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForInactiveSession()
        })

        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeAfterInactiveSession()
        })
    }

    func observeSystemSleepLifecycle(_ notificationCenter: NotificationCenter) {
        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.suspendForSystemSleep()
        })

        spaceObserverTokens.append(notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resumeAfterSystemWake()
        })
    }

    func suspendForSystemSleep() {
        eventBuffer.suspend(.systemSleep)
        stopMouseUpMonitor()
        onSystemSleepChanged(false)
    }

    func resumeAfterSystemWake() {
        eventBuffer.resume(.systemSleep)
        onSystemSleepChanged(true)
        scheduleDelivery()
    }
}
