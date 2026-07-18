import Carbon
import Foundation
import KkaciCore

final class KeyboardShortcutResolver {
    func resolve(_ registrations: [KeyboardShortcutRegistration]) throws -> [ResolvedShortcut] {
        var resolved: [ResolvedShortcut] = []
        var issues: [ShortcutValidationIssue] = []

        for registration in registrations {
            do {
                let shortcut = try Shortcut(parsing: registration.key)
                let keystroke = try KeyboardShortcutKeyCodec.keystroke(for: shortcut)
                let holdModifier = try registration.releaseGroup.map { _ in
                    try inferHoldModifier(from: shortcut, key: registration.key)
                }
                resolved.append(ResolvedShortcut(
                    registration: registration,
                    keystroke: keystroke,
                    holdModifier: holdModifier
                ))
            } catch {
                issues.append(ShortcutValidationIssue(
                    target: registration.target,
                    message: String(describing: error)
                ))
            }
        }

        issues.append(contentsOf: duplicateKeyIssues(in: resolved))
        issues.append(contentsOf: workspaceTerminalKeyIssues(in: resolved))
        guard issues.isEmpty else {
            throw KeyboardShortcutValidationError(issues: issues)
        }
        return resolved
    }

    private func duplicateKeyIssues(in shortcuts: [ResolvedShortcut]) -> [ShortcutValidationIssue] {
        var issues: [ShortcutValidationIssue] = []
        let groups = Dictionary(grouping: shortcuts, by: \.keystroke)
        for duplicates in groups.values where duplicates.count > 1 {
            for shortcut in duplicates {
                let names: [String] = duplicates.compactMap { duplicate in
                    guard duplicate.registration.name != shortcut.registration.name else {
                        return nil
                    }
                    return "\"\(duplicate.registration.name)\""
                }
                issues.append(ShortcutValidationIssue(
                    target: shortcut.registration.target,
                    message: "Already assigned to \(names.joined(separator: ", "))."
                ))
            }
        }
        return issues
    }

    private func workspaceTerminalKeyIssues(in shortcuts: [ResolvedShortcut]) -> [ShortcutValidationIssue] {
        let workspaceShortcuts = shortcuts.filter { shortcut in
            guard case .switchWorkspace? = shortcut.registration.target else {
                return false
            }
            return true
        }
        return duplicateTerminalKeyIssues(in: workspaceShortcuts)
    }

    private func duplicateTerminalKeyIssues(
        in workspaceShortcuts: [ResolvedShortcut]
    ) -> [ShortcutValidationIssue] {
        Dictionary(grouping: workspaceShortcuts, by: \.keystroke.keyCode)
            .values.flatMap { group -> [ShortcutValidationIssue] in
                guard group.count > 1,
                      Set(group.map(\.keystroke)).count > 1
                else {
                    return []
                }

                return group.map { shortcut in
                    let names = group.compactMap { other in
                        other.registration.name == shortcut.registration.name
                            ? nil
                            : "\"\(other.registration.name)\""
                    }
                    return ShortcutValidationIssue(
                        target: shortcut.registration.target,
                        message: "Workspace selection key is also assigned to \(names.joined(separator: ", "))."
                    )
                }
            }
    }

    private func inferHoldModifier(from shortcut: Shortcut, key: String) throws -> UInt32 {
        if shortcut.modifiers.contains(.option) {
            return UInt32(optionKey)
        }
        if shortcut.modifiers.contains(.control) {
            return UInt32(controlKey)
        }
        if shortcut.modifiers.contains(.command) {
            return UInt32(cmdKey)
        }
        if shortcut.modifiers.contains(.shift) {
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

struct Keystroke: Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
}

enum KeyboardShortcutError: Error, CustomStringConvertible {
    case unsupportedKey(String)
    case missingHoldModifier(String)

    var description: String {
        switch self {
        case let .unsupportedKey(key):
            "unsupported key \(key)"
        case let .missingHoldModifier(key):
            "hold shortcut needs a modifier: \(key)"
        }
    }
}

struct ShortcutValidationIssue: Equatable {
    let target: ShortcutTarget?
    let message: String
}

struct KeyboardShortcutValidationError: Error, CustomStringConvertible {
    let issues: [ShortcutValidationIssue]

    var description: String {
        issues.map(\.message).joined(separator: " ")
    }
}
