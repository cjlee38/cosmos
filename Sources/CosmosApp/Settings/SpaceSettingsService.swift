import CosmosCore

protocol SpaceSettingsServing: AnyObject {
    func snapshot() -> SpaceSettingsSnapshot
    func updateShortcut(_ shortcut: String?, for target: ShortcutTarget) throws -> Bool
    func updateMonitor(_ spaceID: SpaceID, displayID: DisplayID) throws
    func addSpaces(_ spaceIDs: [SpaceID], displayID: DisplayID) throws
    func removeSpace(_ spaceID: SpaceID) throws
    func beginShortcutRecording() throws
    func cancelShortcutRecording() throws
    func shortcutRecordingDidFinish(didPersistChange: Bool)
}

final class SpaceSettingsService: SpaceSettingsServing {
    private let log = Log(category: "settings")

    private let controller: SpaceController
    private let configRuntime: ConfigRuntime
    private let actions: any KeyboardShortcutActionHandling
    private let refreshAfterChange: () -> Void

    init(
        controller: SpaceController,
        configRuntime: ConfigRuntime,
        actions: any KeyboardShortcutActionHandling,
        refreshAfterChange: @escaping () -> Void
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.actions = actions
        self.refreshAfterChange = refreshAfterChange
    }

    func snapshot() -> SpaceSettingsSnapshot {
        let config = configRuntime.settingsConfig
        var windowCounts: [SpaceID: Int] = [:]
        for window in controller.currentWindows() {
            guard let space = controller.membership(for: window.id).flatMap(SpaceID.init(rawValue:)) else {
                continue
            }
            windowCounts[space, default: 0] += 1
        }
        return SpaceSettingsSnapshot(
            config: config,
            monitorSlots: controller.displayTopology.monitorSlots,
            spaceWindowCounts: windowCounts,
            isEditable: configRuntime.isSettingsEditable,
            shortcutValidationMessages: configRuntime.shortcutValidationMessages
        )
    }

    func updateShortcut(_ shortcut: String?, for target: ShortcutTarget) throws -> Bool {
        guard let result = try configRuntime.updateShortcut(shortcut, for: target, actions: actions) else {
            return false
        }
        switch result {
        case .applied:
            log.info("Updated shortcut to \(shortcut ?? "not set")")
        case let .rejected(error):
            log.warning("Saved shortcut but kept previous runtime config: \(error)")
        }
        return true
    }

    func updateMonitor(_ spaceID: SpaceID, displayID: DisplayID) throws {
        let monitorSlot = try controller.displayTopology.monitorSlot(for: displayID)
        guard try editConfig({ config in
            config.assigningSpace(spaceID, toMonitorSlot: monitorSlot)
        }) else { return }
        log.info("Assigned space \(spaceID.rawValue) to display \(displayID)")
    }

    func addSpaces(_ spaceIDs: [SpaceID], displayID: DisplayID) throws {
        let monitorSlot = try controller.displayTopology.monitorSlot(for: displayID)
        guard try editConfig({ config in
            config.addingSpaces(spaceIDs, display: monitorSlot)
        }) else { return }
        log.info(
            "Added spaces \(spaceIDs.map(\.rawValue).joined(separator: ",")) "
                + "to display \(displayID)"
        )
    }

    func removeSpace(_ spaceID: SpaceID) throws {
        guard try editConfig({ config in
            config.removingSpace(spaceID)
        }) else { return }
        log.info("Removed space \(spaceID.rawValue)")
    }

    func beginShortcutRecording() throws {
        try configRuntime.beginShortcutRecording()
    }

    func cancelShortcutRecording() throws {
        try configRuntime.cancelShortcutRecording()
    }

    func shortcutRecordingDidFinish(didPersistChange: Bool) {
        if didPersistChange {
            refreshAfterChange()
        }
    }

    private func editConfig(_ edit: (CosmosConfig) throws -> CosmosConfig?) throws -> Bool {
        guard let result = try configRuntime.editConfig(actions: actions, edit) else {
            return false
        }
        refreshAfterChange()
        if case let .rejected(error) = result {
            log.warning("Saved config but kept previous runtime config: \(error)")
        }
        return true
    }
}
