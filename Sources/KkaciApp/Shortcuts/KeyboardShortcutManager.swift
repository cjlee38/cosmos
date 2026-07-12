import AppKit
import Foundation
import HotKey

struct KeyboardShortcutRegistration {
    let key: String
    let name: String
    let releaseGroup: String?
    let onPress: () -> Void
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
            onRelease: nil
        )
    }

    static func hold(
        key: String,
        name: String,
        releaseGroup: String,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) -> KeyboardShortcutRegistration {
        KeyboardShortcutRegistration(
            key: key,
            name: name,
            releaseGroup: releaseGroup,
            onPress: onPress,
            onRelease: onRelease
        )
    }
}

final class KeyboardShortcutManager {
    private let log = Log(category: "keyboard")

    private let resolver = KeyboardShortcutResolver()
    private var hotKeys: [String: HotKey] = [:]
    private var holdGroups: [String: HoldGroup] = [:]
    private var activeHoldGroups: Set<String> = []
    private lazy var modifierReleaseMonitor = ModifierReleaseMonitor { [weak self] flags in
        self?.handleModifierFlagsChanged(flags)
    }

    deinit {
        unregisterHotKeys()
        modifierReleaseMonitor.stop()
    }

    func start() {
        modifierReleaseMonitor.start()
        log.debug("modifier release monitor started")
    }

    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws {
        let resolvedRegistrations = try resolver.resolve(registrations)
        unregisterHotKeys()
        holdGroups.removeAll()
        activeHoldGroups.removeAll()
        register(resolvedRegistrations)
    }

    private func register(_ registrations: [ResolvedShortcut]) {
        for registration in registrations {
            register(registration)
        }
    }

    private func register(_ registration: ResolvedShortcut) {
        if let releaseGroup = registration.registration.releaseGroup,
           let onRelease = registration.registration.onRelease,
           let holdModifier = registration.holdModifier {
            holdGroups[releaseGroup] = HoldGroup(
                modifier: holdModifier,
                onRelease: onRelease
            )
        }

        log.debug("register key=\(registration.registration.key) action=\(registration.registration.name)")
        hotKeys[registration.keystroke.description] = HotKey(
            key: registration.keystroke.key,
            modifiers: registration.keystroke.modifiers,
            keyDownHandler: { [weak self] in
                self?.handleKeyDown(registration)
            },
            keyUpHandler: { [weak self] in
                self?.logInput("up key=\(registration.registration.key) action=\(registration.registration.name)")
            }
        )
    }

    private func unregisterHotKeys() {
        for hotKey in hotKeys.values {
            hotKey.isPaused = true
        }
        if !hotKeys.isEmpty {
            log.debug("unregister count=\(hotKeys.count)")
        }
        hotKeys.removeAll()
    }

    private func handleKeyDown(_ registration: ResolvedShortcut) {
        logInput("down key=\(registration.registration.key) action=\(registration.registration.name)")
        if let releaseGroup = registration.registration.releaseGroup {
            activeHoldGroups.insert(releaseGroup)
        }
        registration.registration.onPress()
    }

    private func handleModifierFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let releasedGroups = activeHoldGroups.filter { group in
            guard let holdGroup = holdGroups[group] else {
                return true
            }
            return !flags.contains(holdGroup.modifier)
        }

        guard !releasedGroups.isEmpty else {
            return
        }

        for group in releasedGroups {
            activeHoldGroups.remove(group)
            guard let holdGroup = holdGroups[group] else {
                continue
            }

            logInput("release group=\(group)")
            holdGroup.onRelease()
        }
    }

    private func logInput(_ message: String) {
        log.trace(message)
    }
}

private struct HoldGroup {
    let modifier: NSEvent.ModifierFlags
    let onRelease: () -> Void
}
