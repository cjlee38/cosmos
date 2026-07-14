import AppKit
import Foundation

struct KeyboardShortcutRegistration {
    let key: String
    let name: String
    let releaseGroup: String?
    let onPress: () -> Void
    let onRepeat: (() -> Void)?
    let onRelease: (() -> Void)?

    static func press(
        key: String,
        name: String,
        onPress: @escaping () -> Void
    ) -> KeyboardShortcutRegistration {
        KeyboardShortcutRegistration(
            key: key,
            name: name,
            releaseGroup: nil,
            onPress: onPress,
            onRepeat: nil,
            onRelease: nil
        )
    }

    static func hold(
        key: String,
        name: String,
        releaseGroup: String,
        onPress: @escaping () -> Void,
        onRepeat: (() -> Void)? = nil,
        onRelease: @escaping () -> Void
    ) -> KeyboardShortcutRegistration {
        KeyboardShortcutRegistration(
            key: key,
            name: name,
            releaseGroup: releaseGroup,
            onPress: onPress,
            onRepeat: onRepeat,
            onRelease: onRelease
        )
    }
}

final class KeyboardShortcutManager {
    private let log = Log(category: "keyboard")

    private let resolver = KeyboardShortcutResolver()
    private var shortcutsByID: [UInt32: ResolvedShortcut] = [:]
    private var holdGroups: [String: HoldGroup] = [:]
    private var activeHoldGroups: Set<String> = []
    private let repeatController = ShortcutRepeatController()
    private var repeatingShortcutID: UInt32?
    private let makeBackend: (@escaping (CarbonKeyboardEvent) -> Void) -> any CarbonKeyboardHandling
    private let makeModifierFlagsMonitor: (@escaping (UInt32) -> Void) -> any ModifierFlagsMonitoring
    private lazy var backend = makeBackend { [weak self] event in
        self?.handle(event)
    }

    private lazy var modifierFlagsMonitor = makeModifierFlagsMonitor { [weak self] modifiers in
        self?.handleModifierFlagsChanged(modifiers)
    }

    init(
        makeBackend: @escaping (@escaping (CarbonKeyboardEvent) -> Void) -> any CarbonKeyboardHandling = {
            CarbonKeyboardBackend(onEvent: $0)
        },
        makeModifierFlagsMonitor: @escaping (@escaping (UInt32) -> Void) -> any ModifierFlagsMonitoring = {
            ModifierFlagsMonitor(onModifiersChanged: $0)
        }
    ) {
        self.makeBackend = makeBackend
        self.makeModifierFlagsMonitor = makeModifierFlagsMonitor
    }

    func start() throws {
        do {
            try backend.start()
            try modifierFlagsMonitor.start()
        } catch {
            modifierFlagsMonitor.stop()
            backend.stop()
            throw error
        }
        log.debug("Carbon hotkeys and modifier flags monitor started")
    }

    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws {
        stopRepeatingShortcut()
        let resolvedRegistrations = try resolver.resolve(registrations)
        let idsByKeystroke = try backend.replaceHotKeys(resolvedRegistrations.map(\.keystroke))

        shortcutsByID = Dictionary(uniqueKeysWithValues: resolvedRegistrations.map { registration in
            guard let id = idsByKeystroke[registration.keystroke.description] else {
                preconditionFailure("Carbon backend omitted a registered keystroke")
            }
            log.debug("register key=\(registration.registration.key) action=\(registration.registration.name)")
            return (id, registration)
        })
        var nextHoldGroups: [String: HoldGroup] = [:]
        for registration in resolvedRegistrations {
            guard let releaseGroup = registration.registration.releaseGroup,
                  let onRelease = registration.registration.onRelease,
                  let holdModifier = registration.holdModifier
            else {
                continue
            }
            nextHoldGroups[releaseGroup] = HoldGroup(modifier: holdModifier, onRelease: onRelease)
        }
        holdGroups = nextHoldGroups
        activeHoldGroups.removeAll()
    }

    private func handle(_ event: CarbonKeyboardEvent) {
        switch event {
        case let .hotKeyPressed(id):
            guard let registration = shortcutsByID[id] else {
                return
            }
            handleKeyDown(id: id, registration: registration)
        case let .hotKeyReleased(id):
            guard let registration = shortcutsByID[id] else {
                return
            }
            if repeatingShortcutID == id {
                stopRepeatingShortcut()
            }
            logInput("up key=\(registration.registration.key) action=\(registration.registration.name)")
        }
    }

    private func handleKeyDown(id: UInt32, registration: ResolvedShortcut) {
        logInput("down key=\(registration.registration.key) action=\(registration.registration.name)")
        if let releaseGroup = registration.registration.releaseGroup {
            activeHoldGroups.insert(releaseGroup)
        }
        registration.registration.onPress()

        guard let onRepeat = registration.registration.onRepeat else {
            return
        }
        repeatingShortcutID = id
        repeatController.start(action: onRepeat)
    }

    private func handleModifierFlagsChanged(_ modifiers: UInt32) {
        let releasedGroups = activeHoldGroups.filter { group in
            guard let holdGroup = holdGroups[group] else {
                return true
            }
            return modifiers & holdGroup.modifier != holdGroup.modifier
        }

        for group in releasedGroups {
            activeHoldGroups.remove(group)
            guard let holdGroup = holdGroups[group] else {
                continue
            }

            if let repeatingShortcutID,
               shortcutsByID[repeatingShortcutID]?.registration.releaseGroup == group {
                stopRepeatingShortcut()
            }
            logInput("release group=\(group)")
            holdGroup.onRelease()
        }
    }

    private func stopRepeatingShortcut() {
        repeatController.stop()
        repeatingShortcutID = nil
    }

    private func logInput(_ message: String) {
        log.trace(message)
    }
}

private struct HoldGroup {
    let modifier: UInt32
    let onRelease: () -> Void
}

private final class ShortcutRepeatController {
    private var timer: DispatchSourceTimer?

    func start(action: @escaping () -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + NSEvent.keyRepeatDelay,
            repeating: NSEvent.keyRepeatInterval
        )
        timer.setEventHandler(handler: action)
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
