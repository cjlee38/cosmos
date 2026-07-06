import AppKit
import Foundation
import HotKey

final class KeyboardShortcutResolver {
    private let keysByName: [String: Key] = [
        "tab": .tab,
        "1": .one,
        "2": .two,
        "3": .three,
        "4": .four,
        "5": .five,
        "6": .six,
        "7": .seven,
        "8": .eight,
        "9": .nine,
        "0": .zero,
        "a": .a,
        "b": .b,
        "c": .c,
        "d": .d,
        "e": .e,
        "f": .f,
        "g": .g,
        "h": .h,
        "i": .i,
        "j": .j,
        "k": .k,
        "l": .l,
        "m": .m,
        "n": .n,
        "o": .o,
        "p": .p,
        "q": .q,
        "r": .r,
        "s": .s,
        "t": .t,
        "u": .u,
        "v": .v,
        "w": .w,
        "x": .x,
        "y": .y,
        "z": .z
    ]

    func resolve(_ registrations: [KeyboardShortcutRegistration]) throws -> [ResolvedShortcut] {
        var seenKeys: Set<String> = []
        var seenGroups: [String: NSEvent.ModifierFlags] = [:]

        return try registrations.map { registration in
            let keystroke = try parseKeystroke(registration.key)
            guard seenKeys.insert(keystroke.description).inserted else {
                throw KeyboardShortcutError.duplicateKey(registration.key)
            }

            let holdModifier: NSEvent.ModifierFlags?
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

        var modifiers: NSEvent.ModifierFlags = []
        var key: Key?

        for part in parts {
            switch part {
            case "ctrl", "control":
                modifiers.insert(.control)
            case "option", "alt":
                modifiers.insert(.option)
            case "shift":
                modifiers.insert(.shift)
            case "cmd", "command":
                modifiers.insert(.command)
            default:
                if key != nil {
                    throw KeyboardShortcutError.multipleKeys(value)
                }
                key = try parseKey(part)
            }
        }

        guard let key else {
            throw KeyboardShortcutError.missingKey(value)
        }

        return Keystroke(key: key, modifiers: modifiers)
    }

    private func parseKey(_ key: String) throws -> Key {
        guard let resolvedKey = keysByName[key] else {
            throw KeyboardShortcutError.unsupportedKey(key)
        }
        return resolvedKey
    }

    private func inferHoldModifier(from keystroke: Keystroke, key: String) throws -> NSEvent.ModifierFlags {
        if keystroke.modifiers.contains(.option) {
            return .option
        }
        if keystroke.modifiers.contains(.control) {
            return .control
        }
        if keystroke.modifiers.contains(.command) {
            return .command
        }
        if keystroke.modifiers.contains(.shift) {
            return .shift
        }
        throw KeyboardShortcutError.missingHoldModifier(key)
    }
}

struct ResolvedShortcut {
    let registration: KeyboardShortcutRegistration
    let keystroke: Keystroke
    let holdModifier: NSEvent.ModifierFlags?
}

struct Keystroke {
    let key: Key
    let modifiers: NSEvent.ModifierFlags

    var description: String {
        "\(key):\(modifiers.rawValue)"
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
            return "empty key"
        case .missingKey(let value):
            return "missing key in \(value)"
        case .multipleKeys(let value):
            return "multiple keys in \(value)"
        case .unsupportedKey(let key):
            return "unsupported key \(key)"
        case .duplicateKey(let key):
            return "duplicate key \(key)"
        case .missingHoldModifier(let key):
            return "hold shortcut needs a modifier: \(key)"
        case .conflictingHoldGroup(let group):
            return "hold group uses conflicting modifiers: \(group)"
        }
    }
}
