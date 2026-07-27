import Carbon
import CosmosCore
import Foundation

enum CarbonKeyboardEvent {
    case hotKeyPressed(UInt32)
    case hotKeyReleased(UInt32)
}

protocol CarbonKeyboardHandling: AnyObject {
    func start() throws
    func replaceHotKeys(_ keystrokes: [Keystroke]) throws -> [Keystroke: UInt32]
    func stop()
}

final class CarbonKeyboardBackend {
    private static let hotKeySignature = "kkac".utf16.reduce(0) { ($0 << 8) + OSType($1) }

    private let onEvent: (CarbonKeyboardEvent) -> Void
    private var hotKeyHandler: EventHandlerRef?
    private var registrationsByKeystroke: [Keystroke: CarbonHotKeyRegistration] = [:]
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

    func replaceHotKeys(_ keystrokes: [Keystroke]) throws -> [Keystroke: UInt32] {
        guard hotKeyHandler != nil else {
            throw CarbonKeyboardError.notStarted
        }

        let desiredKeystrokes = Set(keystrokes)
        let addedKeystrokes = keystrokes.filter { registrationsByKeystroke[$0] == nil }
        var newlyRegistered: [Keystroke] = []

        do {
            for keystroke in addedKeystrokes {
                let registration = try register(keystroke)
                registrationsByKeystroke[keystroke] = registration
                newlyRegistered.append(keystroke)
            }
        } catch {
            for keystroke in newlyRegistered {
                unregister(keystroke)
            }
            throw error
        }

        let removedKeystrokes = registrationsByKeystroke.keys.filter { !desiredKeystrokes.contains($0) }
        for keystroke in removedKeystrokes {
            unregister(keystroke)
        }

        return Dictionary(uniqueKeysWithValues: registrationsByKeystroke.map { ($0.key, $0.value.id) })
    }

    func stop() {
        for keystroke in Array(registrationsByKeystroke.keys) {
            unregister(keystroke)
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
            panic("RegisterEventHotKey succeeded without returning an EventHotKeyRef")
        }

        return CarbonHotKeyRegistration(id: id, ref: hotKeyRef)
    }

    private func unregister(_ keystroke: Keystroke) {
        guard let registration = registrationsByKeystroke.removeValue(forKey: keystroke) else {
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
            panic("InstallEventHandler succeeded without returning an EventHandlerRef")
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

extension CarbonKeyboardBackend: CarbonKeyboardHandling {}

private struct CarbonHotKeyRegistration {
    let id: UInt32
    let ref: EventHotKeyRef
}

private enum CarbonKeyboardError: Error, CustomStringConvertible {
    case notStarted
    case installEventHandler(OSStatus)
    case registerHotKey(OSStatus)

    var description: String {
        switch self {
        case .notStarted:
            "CarbonKeyboardBackend must be started before registering hotkeys"
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
