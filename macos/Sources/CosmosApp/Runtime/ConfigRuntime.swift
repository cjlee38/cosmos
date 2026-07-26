import Foundation
import CosmosCore

protocol RuntimeConfigControlling: AnyObject {
    var currentConfig: CosmosConfig { get }

    @discardableResult
    func applyConfig(_ config: CosmosConfig) throws -> SpaceSyncSummary
}

extension SpaceController: RuntimeConfigControlling {}

protocol KeyboardShortcutInstalling: AnyObject {
    func replaceShortcuts(_ registrations: [KeyboardShortcutRegistration]) throws
}

extension KeyboardShortcutManager: KeyboardShortcutInstalling {}

enum ConfigRuntimeStatus: Equatable {
    case valid
    case invalid(String)
    case runtimeError(String)
}

enum ConfigErrorMessage {
    static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            if let description = (error as? LocalizedError)?.errorDescription {
                return description
            }
            return String(describing: error)
        }

        switch decodingError {
        case let .dataCorrupted(context):
            return context.underlyingError.map { String(describing: $0) } ?? context.debugDescription
        case let .keyNotFound(_, context),
             let .typeMismatch(_, context),
             let .valueNotFound(_, context):
            return context.debugDescription
        @unknown default:
            return String(describing: decodingError)
        }
    }
}

enum ConfigApplyResult: Equatable {
    case applied
    case rejected(String)
}

final class ConfigRuntime {
    let configURL: URL?
    private(set) var status: ConfigRuntimeStatus
    private(set) var desiredConfig: CosmosConfig?
    private(set) var shortcutValidationMessages: [ShortcutTarget: String] = [:]
    private let configStore: any CosmosConfigStore
    private let controller: any RuntimeConfigControlling
    private let shortcutInstaller: any KeyboardShortcutInstalling
    private let keyboardBindingMapper: KeyboardBindingMapper
    private let shortcutResolver = KeyboardShortcutResolver()
    private var installedRegistrations: [KeyboardShortcutRegistration] = []
    private var isRecordingShortcut = false

    init(
        configStore: any CosmosConfigStore,
        configURL: URL?,
        controller: any RuntimeConfigControlling,
        keyboardShortcutManager: any KeyboardShortcutInstalling,
        keyboardBindingMapper: KeyboardBindingMapper,
        initialLoadError: Error? = nil
    ) {
        self.configStore = configStore
        self.configURL = configURL
        self.controller = controller
        shortcutInstaller = keyboardShortcutManager
        self.keyboardBindingMapper = keyboardBindingMapper
        status = initialLoadError.map { .invalid(ConfigErrorMessage.describe($0)) } ?? .valid
        desiredConfig = initialLoadError == nil ? controller.currentConfig : nil
    }

    var settingsConfig: CosmosConfig {
        desiredConfig ?? controller.currentConfig
    }

    var isSettingsEditable: Bool {
        desiredConfig != nil
    }

    func installInitialShortcuts(actions: any KeyboardShortcutActionHandling) throws {
        do {
            if let desiredConfig, desiredConfig != controller.currentConfig {
                try applyConfigWithShortcuts(desiredConfig, actions: actions)
                recordValid()
            } else {
                try installShortcuts(for: controller.currentConfig, actions: actions)
            }
            return
        } catch {
            guard desiredConfig != nil else {
                throw error
            }
            recordApplyFailure(error)
            guard error is KeyboardShortcutValidationError else {
                throw error
            }
        }

        try applyConfigWithShortcuts(.default, actions: actions)
    }

    func reload(actions: any KeyboardShortcutActionHandling) throws {
        let loadedConfig: CosmosConfig
        do {
            loadedConfig = try configStore.load()
        } catch {
            desiredConfig = nil
            recordInvalid(error)
            throw error
        }

        desiredConfig = loadedConfig
        do {
            try applyConfigWithShortcuts(loadedConfig, actions: actions)
            recordValid()
        } catch {
            recordApplyFailure(error)
            throw error
        }
    }

    @discardableResult
    func updateConfig(
        _ config: CosmosConfig,
        actions: any KeyboardShortcutActionHandling
    ) throws -> ConfigApplyResult {
        try configStore.save(config)
        desiredConfig = config
        do {
            try applyConfigWithShortcuts(config, actions: actions)
            recordValid()
            return .applied
        } catch {
            recordApplyFailure(error)
            return .rejected(ConfigErrorMessage.describe(error))
        }
    }

    @discardableResult
    func updateConfigBeforeRuntimeStart(
        _ config: CosmosConfig,
        actions: any KeyboardShortcutActionHandling
    ) throws -> ConfigApplyResult {
        try configStore.save(config)
        desiredConfig = config
        do {
            try validateShortcuts(for: config, actions: actions)
            recordValid()
            return .applied
        } catch {
            recordApplyFailure(error)
            return .rejected(ConfigErrorMessage.describe(error))
        }
    }

    @discardableResult
    func updateShortcut(
        _ shortcut: String?,
        for target: ShortcutTarget,
        actions: any KeyboardShortcutActionHandling
    ) throws -> ConfigApplyResult? {
        guard let desiredConfig else {
            throw ConfigEditingUnavailableError()
        }
        guard let config = desiredConfig.updatingShortcut(shortcut, for: target),
              config != desiredConfig
        else {
            try cancelShortcutRecording()
            return nil
        }
        return try updateConfig(config, actions: actions)
    }

    @discardableResult
    func updateShortcutBeforeRuntimeStart(
        _ shortcut: String?,
        for target: ShortcutTarget,
        actions: any KeyboardShortcutActionHandling
    ) throws -> ConfigApplyResult? {
        guard let desiredConfig else {
            throw ConfigEditingUnavailableError()
        }
        guard let config = desiredConfig.updatingShortcut(shortcut, for: target),
              config != desiredConfig
        else {
            return nil
        }
        return try updateConfigBeforeRuntimeStart(config, actions: actions)
    }

    @discardableResult
    func editConfig(
        actions: any KeyboardShortcutActionHandling,
        _ edit: (CosmosConfig) throws -> CosmosConfig?
    ) throws -> ConfigApplyResult? {
        guard let desiredConfig else {
            throw ConfigEditingUnavailableError()
        }
        guard let config = try edit(desiredConfig), config != desiredConfig else {
            return nil
        }
        return try updateConfig(config, actions: actions)
    }

    @discardableResult
    func editConfigBeforeRuntimeStart(
        actions: any KeyboardShortcutActionHandling,
        _ edit: (CosmosConfig) throws -> CosmosConfig?
    ) throws -> ConfigApplyResult? {
        guard let desiredConfig else {
            throw ConfigEditingUnavailableError()
        }
        guard let config = try edit(desiredConfig), config != desiredConfig else {
            return nil
        }
        return try updateConfigBeforeRuntimeStart(config, actions: actions)
    }

    func beginShortcutRecording() throws {
        guard !isRecordingShortcut else {
            return
        }
        try shortcutInstaller.replaceShortcuts([])
        isRecordingShortcut = true
    }

    func cancelShortcutRecording() throws {
        guard isRecordingShortcut else {
            return
        }
        do {
            try shortcutInstaller.replaceShortcuts(installedRegistrations)
            isRecordingShortcut = false
        } catch {
            recordApplyFailure(error)
            throw error
        }
    }

    private func applyConfigWithShortcuts(
        _ config: CosmosConfig,
        actions: any KeyboardShortcutActionHandling
    ) throws {
        let previousRegistrations = installedRegistrations
        do {
            let updatedRegistrations = registrations(for: config.configuredShortcuts, actions: actions)
            try shortcutInstaller.replaceShortcuts(updatedRegistrations)
            try controller.applyConfig(config)
            installedRegistrations = updatedRegistrations
            isRecordingShortcut = false
        } catch let applyError {
            do {
                try shortcutInstaller.replaceShortcuts(previousRegistrations)
            } catch let rollbackError {
                throw ConfigReloadTransactionError(
                    applyError: applyError,
                    rollbackError: rollbackError
                )
            }
            installedRegistrations = previousRegistrations
            isRecordingShortcut = false
            throw applyError
        }
    }

    private func installShortcuts(
        for config: CosmosConfig,
        actions: any KeyboardShortcutActionHandling
    ) throws {
        let registrations = registrations(for: config.configuredShortcuts, actions: actions)
        try shortcutInstaller.replaceShortcuts(registrations)
        installedRegistrations = registrations
        isRecordingShortcut = false
    }

    private func registrations(
        for shortcuts: [ConfiguredShortcut],
        actions: any KeyboardShortcutActionHandling
    ) -> [KeyboardShortcutRegistration] {
        keyboardBindingMapper.registrations(for: shortcuts, actions: actions)
    }

    private func validateShortcuts(
        for config: CosmosConfig,
        actions: any KeyboardShortcutActionHandling
    ) throws {
        _ = try shortcutResolver.resolve(registrations(for: config.configuredShortcuts, actions: actions))
    }

    private func recordValid() {
        status = .valid
        shortcutValidationMessages = [:]
    }

    private func recordInvalid(_ error: Error) {
        status = .invalid(ConfigErrorMessage.describe(error))
        guard let validationError = error as? KeyboardShortcutValidationError else {
            shortcutValidationMessages = [:]
            return
        }

        shortcutValidationMessages = validationError.issues.reduce(into: [:]) { messages, issue in
            guard let target = issue.target else {
                return
            }
            messages[target] = [messages[target], issue.message]
                .compactMap { $0 }
                .joined(separator: " ")
        }
    }

    private func recordApplyFailure(_ error: Error) {
        guard error is KeyboardShortcutValidationError else {
            status = .runtimeError(ConfigErrorMessage.describe(error))
            shortcutValidationMessages = [:]
            return
        }
        recordInvalid(error)
    }
}

struct ConfigEditingUnavailableError: Error, CustomStringConvertible {
    var description: String {
        "Config cannot be edited until config.yaml can be loaded."
    }
}

struct ConfigReloadTransactionError: Error, CustomStringConvertible {
    let applyError: Error
    let rollbackError: Error

    var description: String {
        "Config apply failed: \(applyError); shortcut rollback failed: \(rollbackError)"
    }
}
