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

    private var state: WorkspaceState

    public var activeWorkspace: String {
        state.activeWorkspace
    }

    public var workspaces: [String] {
        state.workspaces
    }

    public var currentConfig: KkaciConfig {
        configuration.currentConfig
    }

    public var startupConfigLoadError: Error? {
        configuration.startupLoadError
    }

    public init(
        windowSystem: any WindowSystem,
        displayProvider: any HidePointProviding,
        configStore: (any KkaciConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil,
        isConfigPersistenceEnabled: Bool = true
    ) {
        self.windowSystem = windowSystem
        self.windowStore = WindowRuntimeStore(recordStore: recordStore)
        let configuration = WorkspaceConfigurationRuntime(
            configStore: configStore,
            isPersistenceEnabled: isConfigPersistenceEnabled
        )
        self.configuration = configuration
        self.windowSetSynchronizer = WindowSetSynchronizer(
            windowSystem: windowSystem,
            windowStore: windowStore
        )
        let hiddenWindowOperator = HiddenWindowOperator(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            windowStore: windowStore
        )
        self.hiddenWindowOperator = hiddenWindowOperator
        self.visibilityCoordinator = WorkspaceVisibilityCoordinator(
            windowSystem: windowSystem,
            hiddenWindowOperator: hiddenWindowOperator
        )
        self.startupHiddenWindowRecordApplier = StartupHiddenWindowRecordApplier(
            windowSystem: windowSystem,
            windowStore: windowStore,
            configuration: configuration
        )
        self.navigationCoordinator = WorkspaceNavigationCoordinator(
            windowSystem: windowSystem,
            configuration: configuration,
            visibilityCoordinator: visibilityCoordinator
        )
        self.assignmentCoordinator = WindowAssignmentCoordinator(
            windowSystem: windowSystem,
            configuration: configuration,
            visibilityCoordinator: visibilityCoordinator
        )
        self.emergencyHiddenWindowRestorer = EmergencyHiddenWindowRestorer(
            windowStore: windowStore,
            hiddenWindowOperator: hiddenWindowOperator
        )
        self.state = WorkspaceState(workspaces: configuration.currentConfig.workspaces)
    }

    public func refreshWindows() -> WindowListResult {
        syncWindows()
    }

    func listWindows() -> WindowListResult {
        refreshWindows()
    }

    public func currentWindows() -> WindowListResult {
        WindowListResult(windows: windowStore.windows, sync: .empty)
    }

    @discardableResult
    public func applyExternalWindowSetChange() throws -> WorkspaceSyncSummary {
        try refreshWindowsAndApplyActiveWorkspace()
    }

    public func membership(for id: WindowID) -> String? {
        state.membership(for: id)
    }

    public func isHiddenByWorkspace(_ id: WindowID) -> Bool {
        state.isHidden(id)
    }

    public func workspaceFrame(for id: WindowID) -> WindowFrame? {
        state.hiddenFrame(for: id) ?? windowStore.snapshot(for: id)?.frame
    }

    public func focusedWindowID() -> WindowID? {
        windowSystem.focusedWindowID()
    }

    public func windowIDsByMostRecentFocus(in workspace: String) -> [WindowID] {
        state.windowIDsByMostRecentFocus(in: workspace, currentFocused: windowSystem.focusedWindowID())
    }

    public func assignFocused(to workspace: String) throws -> WindowID {
        _ = syncWindows()
        return try assignmentCoordinator.assignFocused(to: workspace, state: &state)
    }

    public func assignWindow(_ id: WindowID, to workspace: String) throws {
        _ = syncWindows()
        try assignmentCoordinator.assignWindow(id, to: workspace, state: &state)
    }

    func captureVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        try assignmentCoordinator.captureVisibleWindows(result.windows, into: workspace, state: &state)
        return result.sync
    }

    func captureUnassignedVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        try assignmentCoordinator.captureUnassignedVisibleWindows(result.windows, into: workspace, state: &state)
        return result.sync
    }

    @discardableResult
    public func bootstrapWindowState(defaultWorkspace workspace: String) throws -> WindowBootstrapResult {
        let hiddenRecords = try applyHiddenWindowRecordsAtStartup()
        let sync = try captureUnassignedVisibleWindows(into: workspace)
        try applyActiveWorkspaceVisibility()
        return WindowBootstrapResult(hiddenRecords: hiddenRecords, sync: sync)
    }

    func applyHiddenWindowRecordsAtStartup() throws -> HiddenWindowRecordStartupApplyResult {
        let records = try startupHiddenWindowRecordApplier.loadRecords()
        guard !records.isEmpty else {
            return .empty
        }

        _ = syncWindows()
        return try startupHiddenWindowRecordApplier.apply(records: records, state: &state)
    }

    public func restoreHiddenWindowsForShutdown() {
        _ = syncWindows()
        hiddenWindowOperator.restoreForShutdown(state: state)
    }

    public func switchWorkspace(to workspace: String) throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try navigationCoordinator.switchWorkspace(to: workspace, state: &state)
        return sync
    }

    public func syncWorkspaceToFocusedWindow() throws -> FocusedWindowWorkspaceSyncResult {
        _ = syncWindows()
        return try navigationCoordinator.syncWorkspaceToFocusedWindow(state: &state)
    }

    public func switchToNextWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.nextWorkspace(after: activeWorkspace)
        let sync = try switchWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    public func switchToPreviousWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.previousWorkspace(before: activeWorkspace)
        let sync = try switchWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    public func focusNextWindow() -> WindowFocusResult {
        _ = syncWindows()
        return navigationCoordinator.focusCycledWindow(next: true, state: &state)
    }

    public func focusPreviousWindow() -> WindowFocusResult {
        _ = syncWindows()
        return navigationCoordinator.focusCycledWindow(next: false, state: &state)
    }

    public func moveFocusedWindow(to workspace: String) throws -> WindowMoveResult {
        _ = syncWindows()
        return try assignmentCoordinator.moveFocusedWindow(to: workspace, state: &state)
    }

    @discardableResult
    public func createWorkspace(named workspace: String) throws -> String {
        try ensureWorkspace(workspace)
    }

    @discardableResult
    public func applyConfig(_ config: KkaciConfig, enablePersistence: Bool = true) throws -> WorkspaceSyncSummary {
        configuration.apply(config, enablePersistence: enablePersistence, state: &state)
        return try refreshWindowsAndApplyActiveWorkspace()
    }

    public func hideWindow(_ id: WindowID) throws {
        _ = syncWindows()
        try hiddenWindowOperator.hide(id, state: &state, activeWorkspace: activeWorkspace)
    }

    public func restoreWindow(_ id: WindowID, focus: Bool = false) throws -> RestoreResult {
        _ = syncWindows()
        let result = try hiddenWindowOperator.restore(id, state: &state)
        if focus {
            windowSystem.focus(id)
        }
        return result
    }

    public func focusWindow(_ id: WindowID) throws {
        _ = syncWindows()
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        if let workspace = state.membership(for: id), workspace != activeWorkspace {
            throw WorkspaceError.windowNotInActiveWorkspace(id, workspace)
        }

        _ = try hiddenWindowOperator.restore(id, state: &state)
        windowSystem.focus(id)
        state.recordFocus(id, in: activeWorkspace)
    }

    public func restoreAllHiddenWindows() -> RestoreAllHiddenWindowsResult {
        let requestedIDs = state.hiddenWindowIDs
        _ = syncWindows()
        return emergencyHiddenWindowRestorer.restoreAll(requestedIDs: requestedIDs, state: &state)
    }

    private func syncWindows() -> WindowListResult {
        windowSetSynchronizer.refresh(state: &state)
    }

    private func refreshWindowsAndApplyActiveWorkspace() throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try applyActiveWorkspaceVisibility()
        return sync
    }

    private func ensureWorkspace(_ workspace: String) throws -> String {
        try configuration.ensureWorkspace(workspace, state: &state)
    }

    private func applyActiveWorkspaceVisibility(
        focusActiveWorkspace: Bool = false,
        preferredFocus: WindowID? = nil,
        oldFocusedWindow: WindowID? = nil,
        strictWindowIDs: Set<WindowID> = []
    ) throws {
        try visibilityCoordinator.applyActiveWorkspace(
            state: &state,
            focusActiveWorkspace: focusActiveWorkspace,
            preferredFocus: preferredFocus,
            oldFocusedWindow: oldFocusedWindow,
            strictWindowIDs: strictWindowIDs
        )
    }

}
