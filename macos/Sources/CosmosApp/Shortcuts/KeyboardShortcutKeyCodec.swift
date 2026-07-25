import AppKit
import Carbon
import CosmosCore

enum KeyboardShortcutKeyCodec {
    private static let keyCodesByName: [String: UInt32] = [
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

    static func keystroke(for shortcut: Shortcut) throws -> Keystroke {
        var modifiers: UInt32 = 0
        for modifier in shortcut.modifiers {
            switch modifier {
            case .control:
                modifiers |= UInt32(controlKey)
            case .option:
                modifiers |= UInt32(optionKey)
            case .shift:
                modifiers |= UInt32(shiftKey)
            case .command:
                modifiers |= UInt32(cmdKey)
            }
        }
        guard let keyCode = keyCodesByName[shortcut.key] else {
            throw KeyboardShortcutError.unsupportedKey(shortcut.key)
        }
        return Keystroke(keyCode: keyCode, modifiers: modifiers)
    }

    static func shortcutString(for event: NSEvent) -> String? {
        guard let key = keyName(for: event.keyCode) else {
            return nil
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var parts: [String] = []
        if modifiers.contains(.control) {
            parts.append("control")
        }
        if modifiers.contains(.option) {
            parts.append("option")
        }
        if modifiers.contains(.shift) {
            parts.append("shift")
        }
        if modifiers.contains(.command) {
            parts.append("command")
        }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    static func keyName(for keyCode: UInt16) -> String? {
        keyCodesByName.first(where: { $0.value == UInt32(keyCode) })?.key
    }
}
