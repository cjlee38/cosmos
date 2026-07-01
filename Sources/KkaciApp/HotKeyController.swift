import Carbon
import Foundation
import KkaciCore

final class HotKeyController {
    private enum Action {
        case nextWorkspace
        case previousWorkspace
        case nextWindow
        case previousWindow
        case workspace(String)
    }

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?
    private var actionsByID: [UInt32: Action] = [:]
    private let statusMenuController: StatusMenuController
    private let bindings: [HotKeyBinding]

    init(statusMenuController: StatusMenuController, bindings: [HotKeyBinding]) {
        self.statusMenuController = statusMenuController
        self.bindings = bindings
    }

    deinit {
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func registerConfiguredHotKeys() {
        installHandler()

        for binding in bindings {
            do {
                try register(binding)
            } catch {
                statusMenuController.showMessage("Invalid hotkey \(binding.key): \(error)")
            }
        }
    }

    private func installHandler() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            let controller = Unmanaged<HotKeyController>
                .fromOpaque(userData)
                .takeUnretainedValue()
            controller.handleHotKey(id: hotKeyID.id)
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func register(_ binding: HotKeyBinding) throws {
        let action = try parseAction(binding)
        let keystroke = try parseKeystroke(binding.key)
        let id = UInt32(actionsByID.count + 1)
        actionsByID[id] = action
        register(action: action, id: id, keyCode: keystroke.keyCode, modifiers: keystroke.modifiers)
    }

    private func register(action: Action, id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: fourCharCode("KKCI"), id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
        } else {
            actionsByID[id] = nil
            statusMenuController.showMessage("Failed to register hotkey \(describe(action)): \(status)")
        }
    }

    private func handleHotKey(id: UInt32) {
        guard let action = actionsByID[id] else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            switch action {
            case .nextWorkspace:
                statusMenuController.switchToNextWorkspace()
            case .previousWorkspace:
                statusMenuController.switchToPreviousWorkspace()
            case .nextWindow:
                statusMenuController.focusNextWindow()
            case .previousWindow:
                statusMenuController.focusPreviousWindow()
            case .workspace(let workspace):
                statusMenuController.switchWorkspace(named: workspace)
            }
        }
    }

    private func parseAction(_ binding: HotKeyBinding) throws -> Action {
        switch binding.command.lowercased() {
        case "next-workspace":
            return .nextWorkspace
        case "previous-workspace", "prev-workspace":
            return .previousWorkspace
        case "next-window":
            return .nextWindow
        case "previous-window", "prev-window":
            return .previousWindow
        case "workspace":
            guard let workspace = binding.workspace, !workspace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw HotKeyConfigError.missingWorkspace
            }
            return .workspace(workspace)
        default:
            throw HotKeyConfigError.unknownCommand(binding.command)
        }
    }

    private func parseKeystroke(_ value: String) throws -> Keystroke {
        let parts = value
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !parts.isEmpty else {
            throw HotKeyConfigError.emptyKey
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
                    throw HotKeyConfigError.multipleKeys(value)
                }
                keyCode = try parseKeyCode(part)
            }
        }

        guard let keyCode else {
            throw HotKeyConfigError.missingKey(value)
        }

        return Keystroke(keyCode: keyCode, modifiers: modifiers)
    }

    private func parseKeyCode(_ key: String) throws -> UInt32 {
        switch key {
        case "tab": return UInt32(kVK_Tab)
        case "1": return UInt32(kVK_ANSI_1)
        case "2": return UInt32(kVK_ANSI_2)
        case "3": return UInt32(kVK_ANSI_3)
        case "4": return UInt32(kVK_ANSI_4)
        case "5": return UInt32(kVK_ANSI_5)
        case "6": return UInt32(kVK_ANSI_6)
        case "7": return UInt32(kVK_ANSI_7)
        case "8": return UInt32(kVK_ANSI_8)
        case "9": return UInt32(kVK_ANSI_9)
        case "0": return UInt32(kVK_ANSI_0)
        case "a": return UInt32(kVK_ANSI_A)
        case "b": return UInt32(kVK_ANSI_B)
        case "c": return UInt32(kVK_ANSI_C)
        case "d": return UInt32(kVK_ANSI_D)
        case "e": return UInt32(kVK_ANSI_E)
        case "f": return UInt32(kVK_ANSI_F)
        case "g": return UInt32(kVK_ANSI_G)
        case "h": return UInt32(kVK_ANSI_H)
        case "i": return UInt32(kVK_ANSI_I)
        case "j": return UInt32(kVK_ANSI_J)
        case "k": return UInt32(kVK_ANSI_K)
        case "l": return UInt32(kVK_ANSI_L)
        case "m": return UInt32(kVK_ANSI_M)
        case "n": return UInt32(kVK_ANSI_N)
        case "o": return UInt32(kVK_ANSI_O)
        case "p": return UInt32(kVK_ANSI_P)
        case "q": return UInt32(kVK_ANSI_Q)
        case "r": return UInt32(kVK_ANSI_R)
        case "s": return UInt32(kVK_ANSI_S)
        case "t": return UInt32(kVK_ANSI_T)
        case "u": return UInt32(kVK_ANSI_U)
        case "v": return UInt32(kVK_ANSI_V)
        case "w": return UInt32(kVK_ANSI_W)
        case "x": return UInt32(kVK_ANSI_X)
        case "y": return UInt32(kVK_ANSI_Y)
        case "z": return UInt32(kVK_ANSI_Z)
        default:
            throw HotKeyConfigError.unsupportedKey(key)
        }
    }

    private func describe(_ action: Action) -> String {
        switch action {
        case .nextWorkspace:
            return "next-workspace"
        case .previousWorkspace:
            return "previous-workspace"
        case .nextWindow:
            return "next-window"
        case .previousWindow:
            return "previous-window"
        case .workspace(let workspace):
            return "workspace \(workspace)"
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: UInt32 = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + scalar.value
        }
        return result
    }
}

private struct Keystroke {
    let keyCode: UInt32
    let modifiers: UInt32
}

private enum HotKeyConfigError: Error, CustomStringConvertible {
    case emptyKey
    case missingKey(String)
    case multipleKeys(String)
    case unsupportedKey(String)
    case unknownCommand(String)
    case missingWorkspace

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
        case .unknownCommand(let command):
            return "unknown command \(command)"
        case .missingWorkspace:
            return "workspace command needs a workspace"
        }
    }
}
