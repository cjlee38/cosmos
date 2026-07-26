import AppKit
import ApplicationServices
import CoreGraphics
import CosmosCore
import Foundation

enum WindowRuntimeEventKind: Hashable {
    case applicationActivated
    case focusChanged
    case thumbnailChanged
    case layoutChanged
    case windowSetChanged
    case windowDestroyed
    case displayChanged
    case sessionResumed

    var needsThumbnailCapture: Bool {
        self == .thumbnailChanged
    }

    static func kinds(forAXNotification notification: String) -> Set<Self> {
        switch notification {
        case kAXFocusedWindowChangedNotification:
            [.focusChanged]
        case kAXWindowResizedNotification:
            [.thumbnailChanged, .layoutChanged]
        case kAXWindowCreatedNotification:
            [.thumbnailChanged, .windowSetChanged]
        case kAXWindowMiniaturizedNotification,
             kAXWindowDeminiaturizedNotification,
             kAXTitleChangedNotification:
            [.thumbnailChanged]
        case kAXUIElementDestroyedNotification:
            [.windowDestroyed]
        case kAXWindowMovedNotification:
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

enum AXFocusChangeFilter {
    static func acceptsFocusChange(sourcePID: pid_t, frontmostPID: pid_t?) -> Bool {
        sourcePID == frontmostPID
    }
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

    var containsApplicationActivation: Bool {
        events.contains { $0.kind == .applicationActivated }
    }

    var containsFocusChange: Bool {
        events.contains { event in
            event.kind == .applicationActivated || event.kind == .focusChanged
        }
    }

    var containsDisplayChange: Bool {
        events.contains { $0.kind == .displayChanged }
    }

    var containsWindowSetChange: Bool {
        events.contains { event in
            event.kind == .windowSetChanged || event.kind == .windowDestroyed
        }
    }

    func shouldFollowVisibleFocusedWindow(
        focusedWindowID: WindowID?,
        previouslyFocusedWindowID: WindowID?,
        liveWindowIDs: Set<WindowID>
    ) -> Bool {
        if containsFocusChange {
            return true
        }
        if let previouslyFocusedWindowID,
           events.contains(where: {
               $0.kind == .windowDestroyed && $0.windowID == previouslyFocusedWindowID
           }) {
            return true
        }
        if let previouslyFocusedWindowID,
           events.contains(where: {
               $0.kind == .windowDestroyed && $0.windowID == nil
           }),
           !liveWindowIDs.contains(previouslyFocusedWindowID) {
            return true
        }
        guard let focusedWindowID else {
            return false
        }
        return events.contains {
            $0.kind == .layoutChanged && $0.windowID == focusedWindowID
        }
    }

    var containsSessionResume: Bool {
        events.contains { $0.kind == .sessionResumed }
    }

    var isSessionResumeRecovery: Bool {
        containsSessionResume && !containsWindowSetChange && !containsDisplayChange
    }

    var discoveryWindowIDs: Set<WindowID>? {
        containsDisplayChange || containsWindowSetChange || containsSessionResume ? nil : windowIDs
    }

    var needsFullThumbnailRefresh: Bool {
        containsDisplayChange
    }
}

struct WindowRuntimeEventBuffer {
    private(set) var events: Set<WindowRuntimeEvent> = []
    private(set) var isWindowDragActive = false
    private var isDeliveryScheduled = false
    private var isSuspended = false

    mutating func append(_ event: WindowRuntimeEvent) {
        guard !isSuspended else {
            return
        }
        events.insert(event)
    }

    mutating func suspend() {
        isSuspended = true
        isWindowDragActive = false
        events.removeAll()
    }

    mutating func resume() {
        isSuspended = false
    }

    mutating func beginWindowDrag() {
        isWindowDragActive = true
    }

    mutating func endWindowDrag() {
        isWindowDragActive = false
    }

    mutating func reserveDelivery() -> Bool {
        guard !isSuspended, !isWindowDragActive, !isDeliveryScheduled, !events.isEmpty else {
            return false
        }
        isDeliveryScheduled = true
        return true
    }

    mutating func takeDelivery() -> Set<WindowRuntimeEvent>? {
        isDeliveryScheduled = false
        guard !isSuspended, !isWindowDragActive, !events.isEmpty else {
            return nil
        }

        let delivery = events
        events.removeAll()
        return delivery
    }
}

final class WindowEventMonitor {
    private let onEvents: (WindowRuntimeEventBatch) -> Void
    private let onSessionActivityChanged: (Bool) -> Void
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
        onEvents: @escaping (WindowRuntimeEventBatch) -> Void
    ) {
        self.onSessionActivityChanged = onSessionActivityChanged
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
            startOwnWindowDragIfNeeded()
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
            self?.schedule(.init(kind: .windowSetChanged, windowID: nil))
        })

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

    private func suspendForInactiveSession() {
        eventBuffer.suspend()
        stopMouseUpMonitor()
        onSessionActivityChanged(false)
    }

    private func resumeAfterInactiveSession() {
        eventBuffer.resume()
        onSessionActivityChanged(true)
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
        if isMouseDrivenLayoutNotification(notification), isLeftMouseButtonDown {
            startExternalWindowDragIfNeeded()
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

    private func startExternalWindowDragIfNeeded() {
        guard !eventBuffer.isWindowDragActive else {
            return
        }
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            self?.finishWindowDrag()
        }) else {
            return
        }

        globalMouseUpMonitor = monitor
        eventBuffer.beginWindowDrag()
    }

    private func startOwnWindowDragIfNeeded() {
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
        eventBuffer.beginWindowDrag()
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
