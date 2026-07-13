import Carbon
import Foundation

enum CarbonKeyboardEvent {
    case hotKeyPressed(UInt32)
    case hotKeyReleased(UInt32)
}

final class CarbonKeyboardBackend {
    private static let hotKeySignature = "kkac".utf16.reduce(0) { ($0 << 8) + OSType($1) }

    private let onEvent: (CarbonKeyboardEvent) -> Void
    private var hotKeyHandler: EventHandlerRef?
    private var registrationsByKeystroke: [String: CarbonHotKeyRegistration] = [:]
    private var nextHotKeyID: UInt32 = 1

    init(onEvent: @escaping (CarbonKeyboardEvent) -> Void) {
        self.onEvent = onEvent
    }

    deinit {
        stop()
    }

    func start() throws {
        guard hotKeyHandler == nil else {
            return
        }

        do {
            hotKeyHandler = try installHandler(
                target: GetEventDispatcherTarget(),
                eventTypes: [
                    EventTypeSpec(
                        eventClass: OSType(kEventClassKeyboard),
                        eventKind: UInt32(kEventHotKeyPressed)
                    ),
                    EventTypeSpec(
                        eventClass: OSType(kEventClassKeyboard),
                        eventKind: UInt32(kEventHotKeyReleased)
                    )
                ],
                callback: carbonHotKeyEventHandler
            )
        } catch {
            stop()
            throw error
        }
    }

    func replaceHotKeys(_ keystrokes: [Keystroke]) throws -> [String: UInt32] {
        precondition(hotKeyHandler != nil, "CarbonKeyboardBackend must be started before registering hotkeys")

        let desiredKeystrokes = Dictionary(uniqueKeysWithValues: keystrokes.map { ($0.description, $0) })
        let addedKeystrokes = keystrokes.filter { registrationsByKeystroke[$0.description] == nil }
        var newlyRegistered: [String] = []

        do {
            for keystroke in addedKeystrokes {
                let registration = try register(keystroke)
                registrationsByKeystroke[keystroke.description] = registration
                newlyRegistered.append(keystroke.description)
            }
        } catch {
            for description in newlyRegistered {
                unregister(description)
            }
            throw error
        }

        let removedDescriptions = registrationsByKeystroke.keys.filter { desiredKeystrokes[$0] == nil }
        for description in removedDescriptions {
            unregister(description)
        }

        return Dictionary(uniqueKeysWithValues: registrationsByKeystroke.map { ($0.key, $0.value.id) })
    }

    func stop() {
        for description in Array(registrationsByKeystroke.keys) {
            unregister(description)
        }
        removeHandler(&hotKeyHandler)
    }

    fileprivate func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == Self.hotKeySignature
        else {
            return status == noErr ? OSStatus(eventNotHandledErr) : status
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            onEvent(.hotKeyPressed(hotKeyID.id))
        case UInt32(kEventHotKeyReleased):
            onEvent(.hotKeyReleased(hotKeyID.id))
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func register(_ keystroke: Keystroke) throws -> CarbonHotKeyRegistration {
        let id = nextHotKeyID
        nextHotKeyID += 1

        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keystroke.keyCode,
            keystroke.modifiers,
            EventHotKeyID(signature: Self.hotKeySignature, id: id),
            GetEventDispatcherTarget(),
            UInt32(kEventHotKeyNoOptions),
            &hotKeyRef
        )
        guard status == noErr else {
            throw CarbonKeyboardError.registerHotKey(status)
        }
        guard let hotKeyRef else {
            preconditionFailure("RegisterEventHotKey succeeded without returning an EventHotKeyRef")
        }

        return CarbonHotKeyRegistration(id: id, ref: hotKeyRef)
    }

    private func unregister(_ description: String) {
        guard let registration = registrationsByKeystroke.removeValue(forKey: description) else {
            return
        }
        UnregisterEventHotKey(registration.ref)
    }

    private func installHandler(
        target: EventTargetRef,
        eventTypes: [EventTypeSpec],
        callback: EventHandlerUPP
    ) throws -> EventHandlerRef {
        var eventTypes = eventTypes
        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            target,
            callback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        guard status == noErr else {
            throw CarbonKeyboardError.installEventHandler(status)
        }
        guard let handler else {
            preconditionFailure("InstallEventHandler succeeded without returning an EventHandlerRef")
        }
        return handler
    }

    private func removeHandler(_ handler: inout EventHandlerRef?) {
        guard let existingHandler = handler else {
            return
        }
        RemoveEventHandler(existingHandler)
        handler = nil
    }
}

private struct CarbonHotKeyRegistration {
    let id: UInt32
    let ref: EventHotKeyRef
}

private enum CarbonKeyboardError: Error, CustomStringConvertible {
    case installEventHandler(OSStatus)
    case registerHotKey(OSStatus)

    var description: String {
        switch self {
        case let .installEventHandler(status):
            "InstallEventHandler failed with status \(status)"
        case let .registerHotKey(status):
            "RegisterEventHotKey failed with status \(status)"
        }
    }
}

private func carbonHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }
    return Unmanaged<CarbonKeyboardBackend>
        .fromOpaque(userData)
        .takeUnretainedValue()
        .handleHotKeyEvent(event)
}
