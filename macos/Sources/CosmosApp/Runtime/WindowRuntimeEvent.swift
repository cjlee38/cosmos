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
