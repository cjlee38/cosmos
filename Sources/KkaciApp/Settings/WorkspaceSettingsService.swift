import KkaciCore

protocol WorkspaceSettingsServing: AnyObject {
    func snapshot() -> WorkspaceSettingsSnapshot
    func updateShortcut(_ shortcut: String?, for target: ShortcutTarget) throws -> Bool
    func updateMonitor(_ workspaceID: WorkspaceID, displayID: DisplayID) throws
    func addWorkspaces(_ workspaceIDs: [WorkspaceID], displayID: DisplayID) throws
    func removeWorkspace(_ workspaceID: WorkspaceID) throws
    func beginShortcutRecording() throws
    func cancelShortcutRecording() throws
    func shortcutRecordingDidFinish(didPersistChange: Bool)
}

final class WorkspaceSettingsService: WorkspaceSettingsServing {
    private let log = Log(category: "settings")

    private let controller: WorkspaceController
    private let configRuntime: ConfigRuntime
    private let actions: any KeyboardShortcutActionHandling
    private let refreshAfterChange: () -> Void

    init(
        controller: WorkspaceController,
        configRuntime: ConfigRuntime,
        actions: any KeyboardShortcutActionHandling,
        refreshAfterChange: @escaping () -> Void
    ) {
        self.controller = controller
        self.configRuntime = configRuntime
        self.actions = actions
        self.refreshAfterChange = refreshAfterChange
    }

    func snapshot() -> WorkspaceSettingsSnapshot {
        WorkspaceSettingsSnapshot(
            config: configRuntime.settingsConfig,
            monitorSlots: controller.displayTopology.monitorSlots,
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

    func updateMonitor(_ workspaceID: WorkspaceID, displayID: DisplayID) throws {
        let monitorSlot = try controller.displayTopology.monitorSlot(for: displayID)
        guard try editConfig({ config in
            config.assigningWorkspace(workspaceID, toMonitorSlot: monitorSlot)
        }) else { return }
        log.info("Assigned workspace \(workspaceID.rawValue) to display \(displayID)")
    }

    func addWorkspaces(_ workspaceIDs: [WorkspaceID], displayID: DisplayID) throws {
        let monitorSlot = try controller.displayTopology.monitorSlot(for: displayID)
        guard try editConfig({ config in
            config.addingWorkspaces(workspaceIDs, display: monitorSlot)
        }) else { return }
        log.info(
            "Added workspaces \(workspaceIDs.map(\.rawValue).joined(separator: ",")) "
                + "to display \(displayID)"
        )
    }

    func removeWorkspace(_ workspaceID: WorkspaceID) throws {
        guard try editConfig({ config in
            config.removingWorkspace(workspaceID)
        }) else { return }
        log.info("Removed workspace \(workspaceID.rawValue)")
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

    private func editConfig(_ edit: (KkaciConfig) throws -> KkaciConfig?) throws -> Bool {
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
