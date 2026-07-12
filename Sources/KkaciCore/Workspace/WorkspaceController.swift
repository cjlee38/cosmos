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

    private var state: WorkspaceState

    public var activeWorkspace: String {
        state.activeWorkspace
    }

    public var workspaces: [String] {
        state.workspaces
    }

    public var activeWorkspaces: [String] {
        state.workspaces.filter { state.activeWorkspaces.contains($0) }
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
        windowStore = WindowRuntimeStore(recordStore: recordStore)
        monitorSlotResolver = MonitorSlotResolver(displayProvider: displayProvider)
        let configuration = WorkspaceConfigurationRuntime(
            configStore: configStore,
            isPersistenceEnabled: isConfigPersistenceEnabled
        )
        self.configuration = configuration
        windowSetSynchronizer = WindowSetSynchronizer(
            windowSystem: windowSystem,
            windowStore: windowStore,
            monitorSlotResolver: monitorSlotResolver
        )
        let restorableFrameResolver = RestorableFrameResolver(displayProvider: displayProvider)
        let hiddenWindowOperator = HiddenWindowOperator(
            windowSystem: windowSystem,
            displayProvider: displayProvider,
            restorableFrameResolver: restorableFrameResolver,
            windowStore: windowStore
        )
        self.hiddenWindowOperator = hiddenWindowOperator
        visibilityCoordinator = WorkspaceVisibilityCoordinator(
            windowSystem: windowSystem,
            hiddenWindowOperator: hiddenWindowOperator
        )
        startupHiddenWindowRecordApplier = StartupHiddenWindowRecordApplier(
            windowSystem: windowSystem,
            windowStore: windowStore,
            configuration: configuration,
            restorableFrameResolver: restorableFrameResolver
        )
        navigationCoordinator = WorkspaceNavigationCoordinator(
            windowSystem: windowSystem,
            configuration: configuration,
            visibilityCoordinator: visibilityCoordinator
        )
        assignmentCoordinator = WindowAssignmentCoordinator(
            windowSystem: windowSystem,
            configuration: configuration,
            visibilityCoordinator: visibilityCoordinator,
            monitorSlotResolver: monitorSlotResolver
        )
        emergencyHiddenWindowRestorer = EmergencyHiddenWindowRestorer(
            windowStore: windowStore,
            hiddenWindowOperator: hiddenWindowOperator
        )
        state = WorkspaceState(workspaces: configuration.currentConfig.workspaces)
    }
}

public extension WorkspaceController {
    func refreshWindows() -> WindowListResult {
        syncWindows()
    }

    internal func listWindows() -> WindowListResult {
        refreshWindows()
    }

    func currentWindows() -> WindowListResult {
        WindowListResult(windows: windowStore.windows, sync: .empty)
    }

    func windows(in workspace: String) -> [WindowSnapshot] {
        windowStore.windows.filter { window in
            state.membership(for: window.id) == workspace && !window.isMinimized
        }
    }

    @discardableResult
    func applyExternalWindowSetChange() throws -> WorkspaceSyncSummary {
        try applyExternalWindowEvents(followFocusedWindow: false).sync
    }

    func applyExternalWindowEvents(
        followFocusedWindow: Bool
    ) throws -> ExternalWindowEventResult {
        let sync = syncWindows().sync
        let focusedWindowSync: FocusedWindowWorkspaceSyncResult?
        if followFocusedWindow {
            let focusResult = try navigationCoordinator.syncWorkspaceToFocusedWindow(state: &state)
            focusedWindowSync = focusResult
            switch focusResult {
            case .switched:
                break
            case .alreadyActive, .noFocusedWindow, .unmanagedWindow:
                try applyActiveWorkspaceVisibility()
            }
        } else {
            focusedWindowSync = nil
            try applyActiveWorkspaceVisibility()
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

    func isWorkspaceActive(_ workspace: String) -> Bool {
        state.activeWorkspaces.contains(workspace)
    }

    func monitorSlot(for workspace: String) -> MonitorSlot {
        state.monitorSlot(for: workspace)
    }

    func activeWorkspace(on monitorSlot: MonitorSlot) -> String {
        state.activeWorkspace(on: monitorSlot)
    }

    var monitorSlots: [MonitorSlotSnapshot] {
        monitorSlotResolver.slots()
    }

    func assignFocused(to workspace: String) throws -> WindowID {
        _ = syncWindows()
        return try assignmentCoordinator.assignFocused(to: workspace, state: &state)
    }

    func assignWindow(_ id: WindowID, to workspace: String) throws {
        _ = syncWindows()
        try assignmentCoordinator.assignWindow(id, to: workspace, state: &state)
    }

    internal func captureVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        try assignmentCoordinator.captureVisibleWindows(result.windows, into: workspace, state: &state)
        return result.sync
    }

    internal func captureUnassignedVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        try assignmentCoordinator.captureUnassignedVisibleWindows(result.windows, into: workspace, state: &state)
        return result.sync
    }

    @discardableResult
    func bootstrapWindowState(defaultWorkspace workspace: String) throws -> WindowBootstrapResult {
        let hiddenRecords = try applyHiddenWindowRecordsAtStartup()
        _ = try captureInitialVisibleWindows(defaultWorkspace: workspace)
        try applyActiveWorkspaceVisibility()
        return WindowBootstrapResult(hiddenRecords: hiddenRecords)
    }

    internal func applyHiddenWindowRecordsAtStartup() throws -> HiddenWindowRecordStartupApplyResult {
        let records = try startupHiddenWindowRecordApplier.loadRecords()
        guard !records.isEmpty else {
            return .empty
        }

        _ = syncWindows()
        return try startupHiddenWindowRecordApplier.apply(records: records, state: &state)
    }

    func restoreHiddenWindowsForShutdown() {
        _ = syncWindows()
        hiddenWindowOperator.restoreForShutdown(state: state)
    }

    func switchWorkspace(to workspace: String) throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try navigationCoordinator.switchWorkspace(
            to: workspace,
            frontToBackWindowIDs: visibleWindowIDsInZOrder,
            state: &state
        )
        return sync
    }

    func syncWorkspaceToFocusedWindow() throws -> FocusedWindowWorkspaceSyncResult {
        _ = syncWindows()
        return try navigationCoordinator.syncWorkspaceToFocusedWindow(state: &state)
    }

    func switchToNextWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.nextWorkspace(after: activeWorkspace)
        let sync = try switchWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    func switchToPreviousWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.previousWorkspace(before: activeWorkspace)
        let sync = try switchWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    func focusNextWindow() -> WindowFocusResult {
        _ = syncWindows()
        return navigationCoordinator.focusCycledWindow(
            next: true,
            frontToBackWindowIDs: windows(in: activeWorkspace).map(\.id),
            state: state
        )
    }

    func focusPreviousWindow() -> WindowFocusResult {
        _ = syncWindows()
        return navigationCoordinator.focusCycledWindow(
            next: false,
            frontToBackWindowIDs: windows(in: activeWorkspace).map(\.id),
            state: state
        )
    }

    func moveFocusedWindow(to workspace: String) throws -> WindowMoveResult {
        _ = syncWindows()
        return try assignmentCoordinator.moveFocusedWindow(
            to: workspace,
            frontToBackWindowIDs: windows(in: activeWorkspace).map(\.id),
            state: &state
        )
    }

    @discardableResult
    func createWorkspace(named workspace: String) throws -> String {
        try ensureWorkspace(workspace, monitorSlot: currentMonitorSlot())
    }

    @discardableResult
    func applyConfig(_ config: KkaciConfig, enablePersistence: Bool = true) throws -> WorkspaceSyncSummary {
        configuration.apply(config, enablePersistence: enablePersistence, state: &state)
        return try refreshWindowsAndApplyActiveWorkspace()
    }

    func hideWindow(_ id: WindowID) throws {
        _ = syncWindows()
        try hiddenWindowOperator.hide(id, state: &state, activeWorkspace: activeWorkspace)
    }

    func restoreWindow(_ id: WindowID, focus: Bool = false) throws -> RestoreResult {
        _ = syncWindows()
        let result = try hiddenWindowOperator.restore(id, state: &state)
        if focus {
            windowSystem.focus(id)
        }
        return result
    }

    func focusWindow(_ id: WindowID) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let workspace = state.membership(for: id) ?? activeWorkspace
        if workspace != state.activeWorkspace(on: state.monitorSlot(for: workspace)) {
            throw WorkspaceError.windowNotInActiveWorkspace(id, workspace)
        }

        _ = try hiddenWindowOperator.restore(id, state: &state)
        windowSystem.focus(id)
    }

    func restoreAllHiddenWindows() -> RestoreAllHiddenWindowsResult {
        let requestedIDs = state.hiddenWindowIDs
        _ = syncWindows()
        return emergencyHiddenWindowRestorer.restoreAll(requestedIDs: requestedIDs, state: &state)
    }
}

private extension WorkspaceController {
    private var visibleWindowIDsInZOrder: [WindowID] {
        windowStore.windows.filter { !$0.isMinimized }.map(\.id)
    }

    private func syncWindows() -> WindowListResult {
        windowSetSynchronizer.refresh(state: &state)
    }

    private func refreshWindowsAndApplyActiveWorkspace() throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try applyActiveWorkspaceVisibility()
        return sync
    }

    private func captureInitialVisibleWindows(defaultWorkspace workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        try assignmentCoordinator.captureUnassignedVisibleWindowsByMonitor(
            result.windows,
            defaultWorkspace: workspace,
            state: &state
        ) { frame in
            monitorSlotResolver.slot(containing: frame)
        }
        return result.sync
    }

    private func ensureWorkspace(_ workspace: String, monitorSlot: MonitorSlot? = nil) throws -> String {
        try configuration.ensureWorkspace(workspace, state: &state, monitorSlot: monitorSlot)
    }

    private func currentMonitorSlot() -> MonitorSlot {
        if let focusedWindowID = windowSystem.focusedWindowID(),
           let frame = windowSystem.frame(for: focusedWindowID) {
            return monitorSlotResolver.slot(containing: frame)
        }
        return state.monitorSlot(for: activeWorkspace)
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
