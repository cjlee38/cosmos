import Foundation

public final class WorkspaceController {
    private let windowSystem: any WindowSystem
    private let windowStore: WindowRuntimeStore
    private let configuration: WorkspaceConfigurationRuntime
    private let windowSetSynchronizer: WindowSetSynchronizer
    private let hiddenWindowOperator: HiddenWindowOperator
    private let visibilityCoordinator: WorkspaceVisibilityCoordinator
    private let startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier
    private let navigationCoordinator: WorkspaceNavigationCoordinator
    private let assignmentCoordinator: WindowAssignmentCoordinator
    private let emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer
    private let monitorSlotResolver: MonitorSlotResolver
    private let displayCoordinator: WorkspaceDisplayCoordinator

    private var state: WorkspaceState

    public var currentWorkspace: String {
        state.currentWorkspace
    }

    public var workspaces: [String] {
        state.workspaces
    }

    public var visibleWorkspaces: [String] {
        let visibleWorkspaces = state.visibleWorkspaces(
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
        return state.workspaces.filter(visibleWorkspaces.contains)
    }

    public var currentConfig: KkaciConfig {
        configuration.currentConfig
    }

    public var startupConfigLoadError: Error? {
        configuration.startupLoadError
    }

    public init(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        configStore: (any KkaciConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil,
        isConfigPersistenceEnabled: Bool = true
    ) {
        self.windowSystem = windowSystem
        let components = WorkspaceControllerComposition.build(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            configStore: configStore,
            recordStore: recordStore,
            isConfigPersistenceEnabled: isConfigPersistenceEnabled
        )
        windowStore = components.windowStore
        configuration = components.configuration
        windowSetSynchronizer = components.windowSetSynchronizer
        hiddenWindowOperator = components.hiddenWindowOperator
        visibilityCoordinator = components.visibilityCoordinator
        startupHiddenWindowRecordApplier = components.startupHiddenWindowRecordApplier
        navigationCoordinator = components.navigationCoordinator
        assignmentCoordinator = components.assignmentCoordinator
        emergencyHiddenWindowRestorer = components.emergencyHiddenWindowRestorer
        monitorSlotResolver = components.monitorSlotResolver
        displayCoordinator = components.displayCoordinator
        state = components.state
    }
}

public extension WorkspaceController {
    internal func discoverWindows() -> WindowDiscoveryResult {
        syncWindows()
    }

    func currentWindows() -> [WindowSnapshot] {
        windowStore.windows
    }

    func windows(in workspace: String) -> [WindowSnapshot] {
        windowStore.windows.filter { window in
            state.membership(for: window.id) == workspace && !window.isMinimized
        }
    }

    func handleWindowSetChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowEvents(followFocusedWindow: false)
    }

    func handleFocusedWindowChanged() throws -> ExternalWindowEventResult {
        try handleExternalWindowEvents(followFocusedWindow: true)
    }

    func handleDisplayConfigurationChanged() throws -> ExternalWindowEventResult {
        try displayCoordinator.handleDisplayConfigurationChanged(state: &state)
    }

    private func handleExternalWindowEvents(followFocusedWindow: Bool) throws -> ExternalWindowEventResult {
        let sync = syncWindows().sync
        let focusedWindowSync: FocusedWindowWorkspaceSyncResult?
        if followFocusedWindow {
            let focusResult = try navigationCoordinator.syncWorkspaceToFocusedWindow(
                frontToBackWindowIDs: windowStore.windows.filter { !$0.isMinimized }.map(\.id),
                state: &state
            )
            focusedWindowSync = focusResult
            switch focusResult {
            case .switched:
                break
            case .alreadyActive, .noFocusedWindow, .unmanagedWindow:
                try visibilityCoordinator.applyVisibleWorkspaces(state: &state)
            }
        } else {
            focusedWindowSync = nil
            try visibilityCoordinator.applyVisibleWorkspaces(state: &state)
        }

        return ExternalWindowEventResult(
            sync: sync,
            focusedWindowSync: focusedWindowSync
        )
    }

    func membership(for id: WindowID) -> String? {
        state.membership(for: id)
    }

    func isHiddenByWorkspace(_ id: WindowID) -> Bool {
        state.isHidden(id)
    }

    func workspaceFrame(for id: WindowID) -> WindowFrame? {
        state.hiddenFrame(for: id) ?? windowStore.snapshot(for: id)?.frame
    }

    func focusedWindowID() -> WindowID? {
        windowSystem.focusedWindowID()
    }

    func currentFocusedWindowID() -> WindowID? {
        windowStore.focusedWindowID
    }

    func isWorkspaceVisible(_ workspace: String) -> Bool {
        state.visibleWorkspaces(
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        ).contains(workspace)
    }

    func monitorSlot(for workspace: String) -> MonitorSlot {
        state.configuredMonitorSlot(for: workspace)
    }

    func effectiveMonitorSlot(for workspace: String) -> MonitorSlot {
        state.monitorSlot(
            for: workspace,
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
    }

    func visibleWorkspace(on monitorSlot: MonitorSlot) -> String {
        state.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
    }

    var monitorSlots: [MonitorSlotSnapshot] {
        windowStore.monitorSlots
    }

    var displays: [DisplaySnapshot] {
        windowStore.displayTopology.displays
    }

    func assignFocused(to workspace: String) throws -> WindowID? {
        guard let workspace = state.findWorkspace(workspace) else {
            return nil
        }
        _ = syncWindows()
        return try assignmentCoordinator.assignFocused(to: workspace, state: &state)
    }

    @discardableResult
    func assignWindow(_ id: WindowID, to workspace: String) throws -> Bool {
        guard let workspace = state.findWorkspace(workspace) else {
            return false
        }
        _ = syncWindows()
        try assignmentCoordinator.assignWindow(id, to: workspace, state: &state)
        return true
    }

    internal func captureVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary? {
        guard let workspace = state.findWorkspace(workspace) else {
            return nil
        }
        let result = syncWindows()
        try assignmentCoordinator.captureVisibleWindows(result.windows, into: workspace, state: &state)
        return result.sync
    }

    @discardableResult
    func bootstrapWindowState(defaultWorkspace workspace: String) throws -> HiddenWindowRecordStartupApplyResult {
        let hiddenRecords = try applyHiddenWindowRecordsAtStartup()
        _ = try captureInitialVisibleWindows(defaultWorkspace: workspace)
        try visibilityCoordinator.applyVisibleWorkspaces(state: &state)
        return hiddenRecords
    }

    internal func applyHiddenWindowRecordsAtStartup() throws -> HiddenWindowRecordStartupApplyResult {
        let records = try startupHiddenWindowRecordApplier.loadRecords()
        guard !records.isEmpty else {
            return .empty
        }

        _ = syncWindows()
        return try startupHiddenWindowRecordApplier.apply(records: records, state: &state)
    }

    func restoreHiddenWindowsForShutdown() throws {
        _ = syncWindows()
        try hiddenWindowOperator.restoreForShutdown(state: state)
    }

    func switchWorkspace(to workspace: String) throws -> WorkspaceSyncSummary? {
        guard let workspace = state.findWorkspace(workspace) else {
            return nil
        }
        return try switchExistingWorkspace(to: workspace)
    }

    private func switchExistingWorkspace(to workspace: String) throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try navigationCoordinator.switchWorkspace(
            to: workspace,
            frontToBackWindowIDs: windowStore.windows.filter { !$0.isMinimized }.map(\.id),
            state: &state
        )
        return sync
    }

    func switchToNextWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.nextWorkspace(
            after: currentWorkspace,
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
        let sync = try switchExistingWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    func switchToPreviousWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.previousWorkspace(
            before: currentWorkspace,
            availableMonitorSlots: windowStore.displayTopology.availableMonitorSlots
        )
        let sync = try switchExistingWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    func focusNextWindow() -> WindowFocusResult {
        _ = syncWindows()
        return navigationCoordinator.focusCycledWindow(
            next: true,
            frontToBackWindowIDs: windows(in: currentWorkspace).map(\.id),
            state: state
        )
    }

    func focusPreviousWindow() -> WindowFocusResult {
        _ = syncWindows()
        return navigationCoordinator.focusCycledWindow(
            next: false,
            frontToBackWindowIDs: windows(in: currentWorkspace).map(\.id),
            state: state
        )
    }

    func moveFocusedWindow(to workspace: String) throws -> WindowMoveResult? {
        guard let workspace = state.findWorkspace(workspace) else {
            return nil
        }
        _ = syncWindows()
        return try assignmentCoordinator.moveFocusedWindow(
            to: workspace,
            frontToBackWindowIDs: windows(in: currentWorkspace).map(\.id),
            state: &state
        )
    }

    @discardableResult
    func applyConfig(_ config: KkaciConfig, enablePersistence: Bool = true) throws -> WorkspaceSyncSummary {
        try applyConfigTransaction(
            config,
            enablePersistence: enablePersistence,
            saveConfig: false
        )
    }

    @discardableResult
    func updateConfig(_ config: KkaciConfig) throws -> WorkspaceSyncSummary {
        try applyConfigTransaction(config, enablePersistence: nil, saveConfig: true)
    }

    func hideWindow(_ id: WindowID) throws {
        _ = syncWindows()
        try hiddenWindowOperator.hide(id, state: &state, currentWorkspace: currentWorkspace)
    }

    func restoreWindow(_ id: WindowID, focus: Bool = false) throws -> RestoreResult {
        _ = syncWindows()
        let result = try hiddenWindowOperator.restore(id, state: &state)
        if focus {
            windowSystem.focus(id)
            windowStore.updateFocusedWindowID(id)
        }
        return result
    }

    func focusWindow(_ id: WindowID) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let workspace = state.membership(for: id) ?? currentWorkspace
        let availableMonitorSlots = windowStore.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
        if workspace != state.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        ) {
            throw WorkspaceError.windowNotInVisibleWorkspace(id, workspace)
        }

        _ = try hiddenWindowOperator.restore(id, state: &state)
        windowSystem.focus(id)
        windowStore.updateFocusedWindowID(id)
    }

    func restoreAllHiddenWindows() throws -> RestoreAllHiddenWindowsResult {
        let requestedIDs = state.hiddenWindowIDs
        _ = syncWindows()
        return try emergencyHiddenWindowRestorer.restoreAll(requestedIDs: requestedIDs, state: &state)
    }
}

private extension WorkspaceController {
    private func syncWindows(
        reconcileVisibleWindowMonitorMembership: Bool = true
    ) -> WindowDiscoveryResult {
        windowSetSynchronizer.refresh(
            state: &state,
            reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership
        )
    }

    private func applyConfigTransaction(
        _ config: KkaciConfig,
        enablePersistence: Bool?,
        saveConfig: Bool
    ) throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try configuration.applyTransaction(
            config,
            enablePersistence: enablePersistence,
            saveConfig: saveConfig,
            state: &state
        ) { state in
            let requiredWindowIDs = Set(state.assignedWindowIDs)
            let targetFrames = displayCoordinator.targetFramesForConfiguredMonitors(state: state)
            try visibilityCoordinator.applyVisibleWorkspaces(
                state: &state,
                requiredWindowIDs: requiredWindowIDs,
                targetFrames: targetFrames
            )
        }
        return sync
    }

    private func captureInitialVisibleWindows(defaultWorkspace workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        assignmentCoordinator.captureUnassignedVisibleWindowsByMonitor(
            result.windows,
            defaultWorkspace: workspace,
            state: &state
        ) { frame in
            monitorSlotResolver.slot(containing: frame, among: windowStore.monitorSlots)
        }
        return result.sync
    }
}
