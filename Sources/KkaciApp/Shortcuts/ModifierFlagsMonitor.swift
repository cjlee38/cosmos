import Carbon
import CoreGraphics
import Foundation

protocol ModifierFlagsMonitoring: AnyObject {
    func start() throws
    func stop()
}

final class ModifierFlagsMonitor {
    private let onModifiersChanged: (UInt32) -> Void
    private let currentModifierFlags: () -> CGEventFlags
    private let ensureListenEventAccess: () -> Bool
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(
        onModifiersChanged: @escaping (UInt32) -> Void,
        currentModifierFlags: @escaping () -> CGEventFlags = {
            CGEventSource.flagsState(.combinedSessionState)
        },
        ensureListenEventAccess: @escaping () -> Bool = {
            CGPreflightListenEventAccess() || CGRequestListenEventAccess()
        }
    ) {
        self.onModifiersChanged = onModifiersChanged
        self.currentModifierFlags = currentModifierFlags
        self.ensureListenEventAccess = ensureListenEventAccess
    }

    deinit {
        stop()
    }

    func start() throws {
        guard eventTap == nil else {
            return
        }

        guard ensureListenEventAccess() else {
            throw ModifierFlagsMonitorError.listenEventAccessDenied
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: modifierFlagsEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw ModifierFlagsMonitorError.eventTapCreationFailed
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            publishModifiers(event.flags)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            publishModifiers(currentModifierFlags())
        default:
            break
        }
    }

    private func publishModifiers(_ flags: CGEventFlags) {
        let modifiers = carbonModifiers(from: flags)
        // Commit may perform AX work, so return from the event-tap callback first.
        DispatchQueue.main.async { [weak self] in
            self?.onModifiersChanged(modifiers)
        }
    }

    private func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskAlternate) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.maskControl) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.maskCommand) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.maskShift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }
}

extension ModifierFlagsMonitor: ModifierFlagsMonitoring {}

private enum ModifierFlagsMonitorError: Error {
    case listenEventAccessDenied
    case eventTapCreationFailed
}

private func modifierFlagsEventTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    Unmanaged<ModifierFlagsMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handle(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
