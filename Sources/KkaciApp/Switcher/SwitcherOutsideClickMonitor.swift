import AppKit

final class SwitcherOutsideClickMonitor {
    private let log = Log(category: "switcher")

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var overlayFrame = NSRect.zero
    private var onOutsideClick: (() -> Void)?
    private var isActive = false

    deinit {
        invalidate()
    }

    func start(overlayFrame: NSRect, onOutsideClick: @escaping () -> Void) {
        self.overlayFrame = overlayFrame
        self.onOutsideClick = onOutsideClick
        isActive = true

        if eventTap == nil {
            createEventTap()
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    func stop() {
        isActive = false
        onOutsideClick = nil
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    func updateOverlayFrame(_ frame: NSRect) {
        overlayFrame = frame
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            guard isActive, Self.isOutsideClick(at: event.unflippedLocation, overlayFrame: overlayFrame) else {
                return Unmanaged.passUnretained(event)
            }

            isActive = false
            DispatchQueue.main.async { [weak self] in
                self?.onOutsideClick?()
            }
            return nil
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if isActive, let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    static func isOutsideClick(at location: CGPoint, overlayFrame: CGRect) -> Bool {
        !overlayFrame.contains(location)
    }

    private func createEventTap() {
        let mouseDownMask = [
            CGEventType.leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ].reduce(CGEventMask(0)) { mask, type in
            mask | CGEventMask(1 << type.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mouseDownMask,
            callback: switcherOutsideClickEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            log.error("Failed to create outside-click event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
    }

    private func invalidate() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }
}

private func switcherOutsideClickEventTapCallback(
    _: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    return Unmanaged<SwitcherOutsideClickMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}
