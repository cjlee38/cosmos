import AppKit
import Foundation
import CosmosCore

struct KeyboardShortcutRegistration {
    struct HoldActions {
        let onPress: () -> Void
        let onRepeat: (() -> Void)?
        let onRelease: () -> Void
        let onCancel: () -> Void

        init(
            onPress: @escaping () -> Void,
            onRepeat: (() -> Void)? = nil,
            onRelease: @escaping () -> Void,
            onCancel: @escaping () -> Void
        ) {
            self.onPress = onPress
            self.onRepeat = onRepeat
            self.onRelease = onRelease
            self.onCancel = onCancel
        }
    }

    let key: String
    let name: String
    let target: ShortcutTarget?
    let releaseGroup: String?
    let onPress: () -> Void
    let onRepeat: (() -> Void)?
    let onRelease: (() -> Void)?
    let onCancel: (() -> Void)?

    static func press(
        key: String,
        name: String,
        target: ShortcutTarget? = nil,
        onPress: @escaping () -> Void
    ) -> KeyboardShortcutRegistration {
        KeyboardShortcutRegistration(
            key: key,
            name: name,
            target: target,
            releaseGroup: nil,
            onPress: onPress,
            onRepeat: nil,
            onRelease: nil,
            onCancel: nil
        )
    }

    static func hold(
        key: String,
        name: String,
        target: ShortcutTarget? = nil,
        releaseGroup: String,
        actions: HoldActions
    ) -> KeyboardShortcutRegistration {
        KeyboardShortcutRegistration(
            key: key,
            name: name,
            target: target,
            releaseGroup: releaseGroup,
            onPress: actions.onPress,
            onRepeat: actions.onRepeat,
            onRelease: actions.onRelease,
            onCancel: actions.onCancel
        )
    }
}

final class KeyboardShortcutManager {
    private let log = Log(category: "keyboard")

    private let resolver = KeyboardShortcutResolver()
    private var shortcutsByID: [UInt32: ResolvedShortcut] = [:]
    private var activeHoldGroups: [String: HoldGroup] = [:]
    private let repeatController: any ShortcutRepeating
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
        },
        repeatController: any ShortcutRepeating = ShortcutRepeatController()
    ) {
        self.makeBackend = makeBackend
        self.makeModifierFlagsMonitor = makeModifierFlagsMonitor
        self.repeatController = repeatController
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
        let resolvedRegistrations = try resolver.resolve(registrations)
        let idsByKeystroke = try backend.replaceHotKeys(resolvedRegistrations.map(\.keystroke))

        cancelActiveHoldGroups()

        shortcutsByID = Dictionary(uniqueKeysWithValues: resolvedRegistrations.map { registration in
            guard let id = idsByKeystroke[registration.keystroke] else {
                preconditionFailure("Carbon backend omitted a registered keystroke")
            }
            log.debug("register key=\(registration.registration.key) action=\(registration.registration.name)")
            return (id, registration)
        })
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
        if let releaseGroup = registration.registration.releaseGroup,
           let holdModifier = registration.holdModifier,
           let onRelease = registration.registration.onRelease,
           activeHoldGroups[releaseGroup] == nil {
            activeHoldGroups[releaseGroup] = HoldGroup(
                modifier: holdModifier,
                onRelease: onRelease,
                onCancel: registration.registration.onCancel
            )
        }
        registration.registration.onPress()

        guard let onRepeat = registration.registration.onRepeat else {
            return
        }
        repeatingShortcutID = id
        repeatController.start(action: onRepeat)
    }

    private func handleModifierFlagsChanged(_ modifiers: UInt32) {
        let releasedGroups = activeHoldGroups.filter { _, holdGroup in
            return modifiers & holdGroup.modifier != holdGroup.modifier
        }

        for (group, holdGroup) in releasedGroups {
            activeHoldGroups.removeValue(forKey: group)
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

    private func cancelActiveHoldGroups() {
        stopRepeatingShortcut()
        for holdGroup in activeHoldGroups.values {
            holdGroup.onCancel?()
        }
        activeHoldGroups.removeAll()
    }

    private func logInput(_ message: String) {
        log.trace(message)
    }
}

private struct HoldGroup {
    let modifier: UInt32
    let onRelease: () -> Void
    let onCancel: (() -> Void)?
}

protocol ShortcutRepeating: AnyObject {
    func start(action: @escaping () -> Void)
    func stop()
}

final class ShortcutRepeatController: ShortcutRepeating {
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
