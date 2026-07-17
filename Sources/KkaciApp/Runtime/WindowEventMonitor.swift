import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import KkaciCore

enum WindowRuntimeEventKind: Hashable {
    case focusChanged
    case thumbnailChanged
    case layoutChanged
    case windowSetChanged
    case displayChanged

    var needsThumbnailCapture: Bool {
        self == .thumbnailChanged
    }

    static func kinds(forAXNotification notification: String) -> Set<Self> {
        switch notification {
        case kAXFocusedWindowChangedNotification:
            [.focusChanged]
        case kAXWindowResizedNotification:
            [.thumbnailChanged, .layoutChanged]
        case kAXWindowCreatedNotification,
             kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification,
             kAXTitleChangedNotification:
            [.thumbnailChanged]
        case kAXUIElementDestroyedNotification,
             kAXWindowMovedNotification:
            [.layoutChanged]
        default:
            []
        }
    }
}

struct WindowRuntimeEvent: Hashable {
    let kind: WindowRuntimeEventKind
    let windowID: WindowID?
}

struct WindowRuntimeEventBatch {
    let events: Set<WindowRuntimeEvent>

    var windowIDs: Set<WindowID> {
        Set(events.compactMap(\.windowID))
    }

    var windowIDsNeedingCapture: Set<WindowID> {
        Set(events.compactMap { event in
            event.kind.needsThumbnailCapture ? event.windowID : nil
        })
    }

    var shouldFollowFocusedWindow: Bool {
        events.contains { $0.kind == .focusChanged }
    }

    var containsLayoutChange: Bool {
        events.contains { $0.kind == .layoutChanged }
    }

    var containsDisplayChange: Bool {
        events.contains { $0.kind == .displayChanged }
    }

    var needsFullThumbnailRefresh: Bool {
        containsDisplayChange
    }
}

final class WindowEventMonitor {
    private let onEvents: (WindowRuntimeEventBatch) -> Void
    private lazy var axObserverRegistry = AXApplicationObserverRegistry { [weak self] element, notification in
        self?.handleAXNotification(element: element, notification: notification)
    }

    private var workspaceObserverTokens: [NSObjectProtocol] = []
    private var appObserverTokens: [NSObjectProtocol] = []
    private var pendingEvents: Set<WindowRuntimeEvent> = []
    private var deliveryScheduled = false
    private var isWindowDragActive = false
    private var mouseUpMonitor: Any?

    init(onEvents: @escaping (WindowRuntimeEventBatch) -> Void) {
        self.onEvents = onEvents
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
        stopMouseUpMonitor()
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
                self?.schedule(.init(kind: .windowSetChanged, windowID: nil))
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
            self?.schedule(.init(kind: .windowSetChanged, windowID: nil))
        })
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
            schedule(.init(kind: .focusChanged, windowID: nil))
            return
        }
        if axObserverRegistry.canObserve(app) {
            schedule(.init(kind: .focusChanged, windowID: nil))
        }
    }

    private func handleAXNotification(element: AXUIElement, notification: CFString) {
        let kinds = WindowRuntimeEventKind.kinds(forAXNotification: notification as String)
        guard !kinds.isEmpty else {
            return
        }
        if isMouseDrivenLayoutNotification(notification), isLeftMouseButtonDown {
            startWindowDragIfNeeded()
        }
        let windowID = AXClient.windowID(for: element)
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

    private func startWindowDragIfNeeded() {
        guard !isWindowDragActive else {
            return
        }
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.finishWindowDrag()
        }) else {
            return
        }

        isWindowDragActive = true
        mouseUpMonitor = monitor
    }

    private func finishWindowDrag() {
        isWindowDragActive = false
        stopMouseUpMonitor()
        scheduleDelivery()
    }

    private func stopMouseUpMonitor() {
        guard let mouseUpMonitor else {
            return
        }
        NSEvent.removeMonitor(mouseUpMonitor)
        self.mouseUpMonitor = nil
    }

    private func schedule(_ event: WindowRuntimeEvent) {
        pendingEvents.insert(event)
        scheduleDelivery()
    }

    private func scheduleDelivery() {
        guard !isWindowDragActive else {
            return
        }
        guard !deliveryScheduled else {
            return
        }

        deliveryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            deliveryScheduled = false
            guard !isWindowDragActive else {
                return
            }

            let events = pendingEvents
            pendingEvents.removeAll()
            onEvents(WindowRuntimeEventBatch(events: events))
        }
    }
}
