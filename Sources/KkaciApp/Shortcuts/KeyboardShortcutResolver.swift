import Carbon
import Foundation

final class KeyboardShortcutResolver {
    private let keyCodesByName: [String: UInt32] = [
        "tab": UInt32(kVK_Tab),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "0": UInt32(kVK_ANSI_0),
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z)
    ]

    func resolve(_ registrations: [KeyboardShortcutRegistration]) throws -> [ResolvedShortcut] {
        var seenKeys: Set<String> = []
        var seenGroups: [String: UInt32] = [:]

        return try registrations.map { registration in
            let keystroke = try parseKeystroke(registration.key)
            guard seenKeys.insert(keystroke.description).inserted else {
                throw KeyboardShortcutError.duplicateKey(registration.key)
            }

            let holdModifier: UInt32?
            if let releaseGroup = registration.releaseGroup {
                holdModifier = try inferHoldModifier(from: keystroke, key: registration.key)
                if let existingModifier = seenGroups[releaseGroup],
                   existingModifier != holdModifier {
                    throw KeyboardShortcutError.conflictingHoldGroup(releaseGroup)
                }
                seenGroups[releaseGroup] = holdModifier
            } else {
                holdModifier = nil
            }

            return ResolvedShortcut(
                registration: registration,
                keystroke: keystroke,
                holdModifier: holdModifier
            )
        }
    }

    private func parseKeystroke(_ value: String) throws -> Keystroke {
        let parts = value
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw KeyboardShortcutError.emptyKey
        }

        var modifiers: UInt32 = 0
        var keyCode: UInt32?

        for part in parts {
            switch part {
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "option", "alt":
                modifiers |= UInt32(optionKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            default:
                if keyCode != nil {
                    throw KeyboardShortcutError.multipleKeys(value)
                }
                keyCode = try parseKeyCode(part)
            }
        }

        guard let keyCode else {
            throw KeyboardShortcutError.missingKey(value)
        }

        return Keystroke(keyCode: keyCode, modifiers: modifiers)
    }

    private func parseKeyCode(_ key: String) throws -> UInt32 {
        guard let keyCode = keyCodesByName[key] else {
            throw KeyboardShortcutError.unsupportedKey(key)
        }
        return keyCode
    }

    private func inferHoldModifier(from keystroke: Keystroke, key: String) throws -> UInt32 {
        if keystroke.modifiers & UInt32(optionKey) != 0 {
            return UInt32(optionKey)
        }
        if keystroke.modifiers & UInt32(controlKey) != 0 {
            return UInt32(controlKey)
        }
        if keystroke.modifiers & UInt32(cmdKey) != 0 {
            return UInt32(cmdKey)
        }
        if keystroke.modifiers & UInt32(shiftKey) != 0 {
            return UInt32(shiftKey)
        }
        throw KeyboardShortcutError.missingHoldModifier(key)
    }
}

struct ResolvedShortcut {
    let registration: KeyboardShortcutRegistration
    let keystroke: Keystroke
    let holdModifier: UInt32?
}

struct Keystroke {
    let keyCode: UInt32
    let modifiers: UInt32

    var description: String {
        "\(keyCode):\(modifiers)"
    }
}

enum KeyboardShortcutError: Error, CustomStringConvertible {
    case emptyKey
    case missingKey(String)
    case multipleKeys(String)
    case unsupportedKey(String)
    case duplicateKey(String)
    case missingHoldModifier(String)
    case conflictingHoldGroup(String)

    var description: String {
        switch self {
        case .emptyKey:
            "empty key"
        case let .missingKey(value):
            "missing key in \(value)"
        case let .multipleKeys(value):
            "multiple keys in \(value)"
        case let .unsupportedKey(key):
            "unsupported key \(key)"
        case let .duplicateKey(key):
            "duplicate key \(key)"
        case let .missingHoldModifier(key):
            "hold shortcut needs a modifier: \(key)"
        case let .conflictingHoldGroup(group):
            "hold group uses conflicting modifiers: \(group)"
        }
    }
}
