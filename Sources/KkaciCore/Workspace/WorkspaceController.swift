import Foundation

public final class WorkspaceController {
    private let windowSystem: any WindowSystem
    private let windowCache: WindowStateCache
    private let runtimeSynchronizer: WorkspaceRuntimeSynchronizer
    private let hiddenWindowOperator: HiddenWindowOperator
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator
    private let startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier
    private let navigationCoordinator: WorkspaceNavigationCoordinator
    private let assignmentCoordinator: WindowAssignmentCoordinator
    private let emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer
    private let displayCoordinator: WorkspaceDisplayCoordinator
    private let initialConfigLoadError: Error?

    private var state: WorkspaceState

    public var currentWorkspace: String {
        state.currentWorkspace.rawValue
    }

    public var workspaces: [String] {
        state.workspaces.map(\.rawValue)
    }

    public var visibleWorkspaces: [String] {
        let visibleWorkspaces = state.visibleWorkspaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
        return state.workspaces.filter(visibleWorkspaces.contains).map(\.rawValue)
    }

    public var currentConfig: KkaciConfig {
        state.currentConfig
    }

    public var startupConfigLoadError: Error? {
        initialConfigLoadError
    }

    public init(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        hidePointProvider: (any HidePointProviding)? = nil,
        configStore: (any KkaciConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil
    ) {
        self.windowSystem = windowSystem
        let components = WorkspaceControllerComposition.build(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            hidePointProvider: hidePointProvider,
            configStore: configStore,
            recordStore: recordStore
        )
        windowCache = components.windowCache
        runtimeSynchronizer = components.runtimeSynchronizer
        hiddenWindowOperator = components.hiddenWindowOperator
        visibilityCoordinator = components.visibilityCoordinator
        startupHiddenWindowRecordApplier = components.startupHiddenWindowRecordApplier
        navigationCoordinator = components.navigationCoordinator
        assignmentCoordinator = components.assignmentCoordinator
        emergencyHiddenWindowRestorer = components.emergencyHiddenWindowRestorer
        displayCoordinator = components.displayCoordinator
        initialConfigLoadError = components.startupConfigLoadError
        state = components.state
    }
}

public extension WorkspaceController {
    func currentWindows() -> [WindowSnapshot] {
        windowCache.windows
    }

    func windows(in workspace: String) -> [WindowSnapshot] {
        guard let workspace = state.findWorkspace(workspace) else {
            return []
        }
        return windowCache.windows.filter { window in
            state.membership(for: window.id) == workspace && !window.isMinimized
        }
    }

    func handleWindowSetChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange())
    }

    func handleOwnWindowVisibilityChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange())
    }

    func handleFocusedWindowChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange(focusPolicy: .always))
    }

    func handleWindowLayoutChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange(focusPolicy: .visibleFocusedWindow))
    }

    func handleDisplayConfigurationChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowChange(ExternalWindowChange(displayConfigurationChanged: true))
    }

    func handleExternalWindowChange(_ change: ExternalWindowChange) throws -> ExternalWindowEventResult {
        let sync: WorkspaceSyncSummary
        let targetFrames: [WindowID: WindowFrame]
        if change.displayConfigurationChanged {
            let displaySync = try displayCoordinator.synchronizeDisplayConfiguration(state: &state)
            sync = displaySync.sync
            targetFrames = displaySync.targetFrames
        } else {
            sync = try syncWindows()
            targetFrames = [:]
        }

        let focusedWindowSync: FocusedWindowWorkspaceSyncResult?
        if change.focusPolicy.shouldFollow(focusedWindowID: windowCache.focusedWindowID, state: state) {
            let focusResult = try navigationCoordinator.syncWorkspaceToFocusedWindow(
                frontToBackWindowIDs: windowCache.windows.filter { !$0.isMinimized }.map(\.id),
                targetFrames: targetFrames,
                state: &state
            )
            focusedWindowSync = focusResult
            switch focusResult {
            case .switched:
                break
            case .alreadyActive, .noFocusedWindow, .unmanagedWindow:
                try visibilityCoordinator.applyVisibleWorkspaces(
                    state: &state,
                    targetFrames: targetFrames
                )
            }
        } else {
            focusedWindowSync = nil
            try visibilityCoordinator.applyVisibleWorkspaces(
                state: &state,
                targetFrames: targetFrames
            )
        }

        return ExternalWindowEventResult(
            sync: sync,
            focusedWindowSync: focusedWindowSync
        )
    }

    func membership(for id: WindowID) -> String? {
        state.membership(for: id)?.rawValue
    }

    func isHiddenByWorkspace(_ id: WindowID) -> Bool {
        state.isHidden(id)
    }

    func workspaceFrame(for id: WindowID) -> WindowFrame? {
        state.hiddenFrame(for: id) ?? windowCache.snapshot(for: id)?.frame
    }

    func systemFocusedWindowID() -> WindowID? {
        windowSystem.focusedWindowID()
    }

    func cachedFocusedWindowID() -> WindowID? {
        windowCache.focusedWindowID
    }

    func isWorkspaceVisible(_ workspace: String) -> Bool {
        guard let workspace = state.findWorkspace(workspace) else {
            return false
        }
        return state.visibleWorkspaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        ).contains(workspace)
    }

    func effectiveMonitorSlot(for workspace: String) -> MonitorSlot {
        guard let workspace = state.findWorkspace(workspace) else {
            return 1
        }
        return state.monitorSlot(
            for: workspace,
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
    }

    func visibleWorkspace(on monitorSlot: MonitorSlot) -> String {
        state.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        ).rawValue
    }

    var displayTopology: DisplayTopologySnapshot {
        windowCache.displayTopology
    }

    @discardableResult
    func bootstrapWindowState() throws -> HiddenWindowRecordStartupApplyResult {
        let hiddenRecords = try applyHiddenWindowRecordsAtStartup()
        _ = try syncWindows()
        try visibilityCoordinator.applyVisibleWorkspaces(state: &state)
        return hiddenRecords
    }

    internal func applyHiddenWindowRecordsAtStartup() throws -> HiddenWindowRecordStartupApplyResult {
        let records = try startupHiddenWindowRecordApplier.loadRecords()
        guard !records.isEmpty else {
            return .empty
        }

        _ = try syncWindows()
        return try startupHiddenWindowRecordApplier.apply(records: records, state: &state)
    }

    func restoreHiddenWindowsForShutdown() throws {
        // Recovery must use the last valid handles when a fresh AX snapshot is unavailable.
        _ = try? syncWindows()
        try hiddenWindowOperator.restoreForShutdown(state: state)
    }

    func switchWorkspace(to workspace: String) throws -> WorkspaceSyncSummary? {
        guard let workspace = state.findWorkspace(workspace) else {
            return nil
        }
        return try switchExistingWorkspace(to: workspace)
    }

    private func switchExistingWorkspace(to workspace: WorkspaceID) throws -> WorkspaceSyncSummary {
        let sync = try syncWindows()
        try navigationCoordinator.switchWorkspace(
            to: workspace,
            frontToBackWindowIDs: windowCache.windows.filter { !$0.isMinimized }.map(\.id),
            state: &state
        )
        return sync
    }

    func moveFocusedWindow(to workspace: String) throws -> WindowMoveResult? {
        guard let workspace = state.findWorkspace(workspace) else {
            return nil
        }
        _ = try syncWindows()
        return try assignmentCoordinator.moveFocusedWindow(
            to: workspace,
            frontToBackWindowIDs: windows(in: currentWorkspace).map(\.id),
            state: &state
        )
    }

    @discardableResult
    func applyConfig(_ config: KkaciConfig) throws -> WorkspaceSyncSummary {
        try applyConfigTransaction(config)
    }

    func focusWindow(_ id: WindowID) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let workspace = state.membership(for: id) ?? state.currentWorkspace
        let availableMonitorSlots = windowCache.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
        if workspace != state.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        ) {
            throw WorkspaceError.windowNotInVisibleWorkspace(id, workspace.rawValue)
        }

        _ = try hiddenWindowOperator.restore(id, state: &state)
        windowSystem.focus(id)
        windowCache.updateFocusedWindowID(windowSystem.focusedWindowID())
    }

    func restoreAllHiddenWindows() throws -> RestoreAllHiddenWindowsResult {
        let requestedIDs = state.hiddenWindowIDs
        // Recovery must use the last valid handles when a fresh AX snapshot is unavailable.
        _ = try? syncWindows()
        return try emergencyHiddenWindowRestorer.restoreAll(requestedIDs: requestedIDs, state: &state)
    }
}

private extension ExternalWindowFocusPolicy {
    func shouldFollow(focusedWindowID: WindowID?, state: WorkspaceState) -> Bool {
        switch self {
        case .never:
            false
        case .always:
            true
        case .visibleFocusedWindow:
            focusedWindowID.map { !state.isHidden($0) } ?? false
        }
    }
}

private extension WorkspaceController {
    private func syncWindows(
        reconcileVisibleWindowMonitorMembership: Bool = true
    ) throws -> WorkspaceSyncSummary {
        try runtimeSynchronizer.synchronize(
            state: &state,
            reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership
        )
    }

    private func applyConfigTransaction(_ config: KkaciConfig) throws -> WorkspaceSyncSummary {
        let sync = try syncWindows()
        let previousState = state
        state.applyConfig(config)
        do {
            let mustSucceedWindowIDs = Set(state.assignedWindowIDs)
            let targetFrames = displayCoordinator.targetFramesForConfiguredMonitors(state: state)
            try visibilityCoordinator.applyVisibleWorkspaces(
                state: &state,
                mustSucceedWindowIDs: mustSucceedWindowIDs,
                targetFrames: targetFrames
            )
        } catch let applyError {
            try visibilityCoordinator.rollback(
                after: applyError,
                to: previousState,
                focusedWindowID: windowCache.focusedWindowID,
                state: &state
            )
            throw applyError
        }
        return sync
    }
}
