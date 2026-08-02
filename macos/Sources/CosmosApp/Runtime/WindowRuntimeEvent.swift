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
    case userLayoutChanged
    case windowSetChanged
    case windowDestroyed
    case applicationTerminated
    case displayChanged
    case sessionResumed
    case continuityRecovery

    var needsThumbnailCapture: Bool {
        self == .thumbnailChanged
    }

    var mustSurviveObservationSuspension: Bool {
        self == .applicationTerminated
            || self == .windowDestroyed
            || self == .displayChanged
    }

    var isRecoveryRequest: Bool {
        self == .sessionResumed || self == .continuityRecovery
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

enum WindowRuntimeRecoveryReason: Equatable {
    case screenLock
    case userSession
    case systemSleep
    case display

    var requiresDisplayRecovery: Bool {
        self == .systemSleep || self == .display
    }

    var eventKind: WindowRuntimeEventKind {
        switch self {
        case .screenLock, .userSession:
            .sessionResumed
        case .systemSleep, .display:
            .continuityRecovery
        }
    }
}

extension WindowRuntimeRecoveryReason: CustomStringConvertible {
    var description: String {
        switch self {
        case .screenLock: "screen-lock"
        case .userSession: "user-session"
        case .systemSleep: "system-sleep"
        case .display: "display"
        }
    }
}

struct WindowRuntimeEvent: Hashable {
    let kind: WindowRuntimeEventKind
    let windowID: WindowID?
    let processID: pid_t?

    init(kind: WindowRuntimeEventKind, windowID: WindowID?, processID: pid_t? = nil) {
        self.kind = kind
        self.windowID = windowID
        self.processID = processID
    }
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
        events.contains { $0.kind == .displayChanged || $0.kind == .continuityRecovery }
    }

    var containsWindowSetChange: Bool {
        events.contains { event in
            event.kind == .windowSetChanged
                || event.kind == .windowDestroyed
                || event.kind == .applicationTerminated
        }
    }

    var terminatedApplicationPIDs: Set<pid_t> {
        Set(events.compactMap { event in
            event.kind == .applicationTerminated ? event.processID : nil
        })
    }

    var destroyedWindowIDs: Set<WindowID> {
        Set(events.compactMap { event in
            event.kind == .windowDestroyed ? event.windowID : nil
        })
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
            ($0.kind == .layoutChanged || $0.kind == .userLayoutChanged)
                && $0.windowID == focusedWindowID
        }
    }

    func focusPolicy(
        discovery: WindowDiscoverySnapshot,
        previouslyFocusedWindowID: WindowID?,
        suppressFocus: Bool
    ) -> ExternalWindowFocusPolicy {
        if suppressFocus {
            return .never
        }
        if containsApplicationActivation {
            return .always
        }
        if shouldFollowVisibleFocusedWindow(
            focusedWindowID: discovery.focusedWindowID,
            previouslyFocusedWindowID: previouslyFocusedWindowID,
            liveWindowIDs: Set(discovery.windows.map(\.id))
        ) {
            return .visibleFocusedWindow
        }
        return .never
    }

    var userMovedWindowIDs: Set<WindowID> {
        Set(events.compactMap { event in
            event.kind == .userLayoutChanged ? event.windowID : nil
        })
    }

    var containsRecoveryRequest: Bool {
        events.contains { $0.kind == .sessionResumed || $0.kind == .continuityRecovery }
    }

    var usesSessionRecoveryDiscovery: Bool {
        if events.contains(where: { $0.kind == .continuityRecovery }) {
            return true
        }
        return containsRecoveryRequest && !containsWindowSetChange && !containsDisplayChange
    }

    var discoveryWindowIDs: Set<WindowID>? {
        containsDisplayChange || containsWindowSetChange || containsRecoveryRequest ? nil : windowIDs
    }

    var needsFullThumbnailRefresh: Bool {
        containsDisplayChange
    }
}

enum WindowObservationSuspension: Hashable {
    case screenLock
    case userSession
    case systemSleep

    var recoveryReason: WindowRuntimeRecoveryReason {
        switch self {
        case .screenLock: .screenLock
        case .userSession: .userSession
        case .systemSleep: .systemSleep
        }
    }
}

extension WindowObservationSuspension: CustomStringConvertible {
    var description: String {
        switch self {
        case .screenLock: "screen-lock"
        case .userSession: "user-session"
        case .systemSleep: "system-sleep"
        }
    }
}

struct WindowObservationState {
    private(set) var suspensionReasons: Set<WindowObservationSuspension> = []

    var isActive: Bool {
        suspensionReasons.isEmpty
    }

    mutating func set(
        _ reason: WindowObservationSuspension,
        isSuspended: Bool
    ) -> WindowObservationTransition? {
        let wasActive = isActive
        let changed = if isSuspended {
            suspensionReasons.insert(reason).inserted
        } else {
            suspensionReasons.remove(reason) != nil
        }
        guard changed else {
            return nil
        }
        return WindowObservationTransition(
            beganSuspension: wasActive && !isActive,
            isActive: isActive,
            activeReasons: suspensionReasons
        )
    }
}

struct WindowObservationTransition {
    let beganSuspension: Bool
    let isActive: Bool
    let activeReasons: Set<WindowObservationSuspension>
}

struct WindowRuntimeEventBuffer {
    private(set) var events: Set<WindowRuntimeEvent> = []
    private(set) var isWindowDragActive = false
    private var draggedWindowID: WindowID?
    private var isDeliveryScheduled = false
    private var suspensionReasons: Set<WindowObservationSuspension> = []

    private var isSuspended: Bool {
        !suspensionReasons.isEmpty
    }

    mutating func append(_ event: WindowRuntimeEvent) {
        guard !isSuspended || event.kind.mustSurviveObservationSuspension else {
            return
        }
        if isWindowDragActive,
           event.kind == .layoutChanged,
           event.windowID == draggedWindowID {
            events.insert(WindowRuntimeEvent(
                kind: .userLayoutChanged,
                windowID: event.windowID,
                processID: event.processID
            ))
        } else {
            events.insert(event)
        }
    }

    mutating func suspend(_ reason: WindowObservationSuspension = .userSession) {
        suspensionReasons.insert(reason)
        isWindowDragActive = false
        draggedWindowID = nil
        events = events.filter(\.kind.mustSurviveObservationSuspension)
    }

    mutating func resume(_ reason: WindowObservationSuspension = .userSession) {
        suspensionReasons.remove(reason)
    }

    mutating func beginWindowDrag(windowID: WindowID? = nil) {
        isWindowDragActive = true
        draggedWindowID = windowID
    }

    mutating func endWindowDrag() {
        isWindowDragActive = false
        draggedWindowID = nil
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
