import Foundation

public final class SpaceController {
    private let windowSystem: any WindowSystem
    private let windowCache: WindowStateCache
    private let runtimeSynchronizer: SpaceRuntimeSynchronizer
    private let hiddenWindowOperator: HiddenWindowOperator
    private let visibilityCoordinator: SpaceVisibilityCoordinator
    private let startupHiddenWindowRecordApplier: StartupHiddenWindowRecordApplier
    private let navigationCoordinator: SpaceNavigationCoordinator
    private let assignmentCoordinator: WindowAssignmentCoordinator
    private let emergencyHiddenWindowRestorer: EmergencyHiddenWindowRestorer
    private let displayCoordinator: SpaceDisplayCoordinator
    private let initialConfigLoadError: Error?

    private var state: SpaceState

    public var currentSpace: String {
        state.currentSpace.rawValue
    }

    public var spaces: [String] {
        state.spaces.map(\.rawValue)
    }

    public var spacesByRecency: [String] {
        state.spacesByRecency.map(\.rawValue)
    }

    public var visibleSpaces: [String] {
        let visibleSpaces = state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
        return state.spaces.filter(visibleSpaces.contains).map(\.rawValue)
    }

    public var currentConfig: CosmosConfig {
        state.currentConfig
    }

    public var startupConfigLoadError: Error? {
        initialConfigLoadError
    }

    public init(
        windowSystem: any WindowSystem,
        displayProvider: any DisplayProviding,
        hidePointProvider: (any HidePointProviding)? = nil,
        configStore: (any CosmosConfigStore)? = nil,
        recordStore: (any HiddenWindowRecordStore)? = nil
    ) {
        self.windowSystem = windowSystem
        let components = SpaceControllerComposition.build(
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

public extension SpaceController {
    func currentWindows() -> [WindowSnapshot] {
        windowCache.windows
    }

    func windows(in space: String) -> [WindowSnapshot] {
        guard let space = state.findSpace(space) else {
            return []
        }
        return windowCache.windows.filter { window in
            state.membership(for: window.id) == space && !window.isMinimized
        }
    }

    func handleExternalWindowChange(_ change: ExternalWindowChange) throws -> ExternalWindowEventResult {
        let sync: SpaceSyncSummary
        let targetFrames: [WindowID: WindowFrame]
        if change.displayConfigurationChanged {
            let displaySync = try displayCoordinator.synchronizeDisplayConfiguration(state: &state)
            sync = displaySync.sync
            targetFrames = displaySync.targetFrames
        } else {
            sync = try syncWindows()
            targetFrames = [:]
        }

        return try finishExternalWindowChange(
            change,
            sync: sync,
            targetFrames: targetFrames
        )
    }

    func discoverWindows(
        windowIDs: Set<WindowID>?,
        mode: WindowDiscoveryMode = .normal
    ) throws -> WindowDiscoverySnapshot {
        try windowSystem.discover(windowIDs: windowIDs, mode: mode)
    }

    func applyExternalWindowChange(
        _ change: ExternalWindowChange,
        discovery: WindowDiscoverySnapshot
    ) throws -> ExternalWindowEventResult? {
        let sync: SpaceSyncSummary
        let targetFrames: [WindowID: WindowFrame]
        if change.displayConfigurationChanged {
            guard let displaySync = try displayCoordinator.applyDisplayConfiguration(
                discovery,
                state: &state
            ) else {
                return nil
            }
            sync = displaySync.sync
            targetFrames = displaySync.targetFrames
        } else {
            guard let appliedSync = runtimeSynchronizer.apply(
                discovery,
                displayTopology: windowCache.displayTopology,
                state: &state
            ) else {
                return nil
            }
            sync = appliedSync
            targetFrames = [:]
        }

        return try finishExternalWindowChange(
            change,
            sync: sync,
            targetFrames: targetFrames
        )
    }

    private func finishExternalWindowChange(
        _ change: ExternalWindowChange,
        sync: SpaceSyncSummary,
        targetFrames: [WindowID: WindowFrame]
    ) throws -> ExternalWindowEventResult {
        let focusedWindowSync: FocusedWindowSpaceSyncResult?
        if change.focusPolicy.shouldFollow(focusedWindowID: windowCache.focusedWindowID, state: state) {
            let focusResult = try navigationCoordinator.syncSpaceToFocusedWindow(
                frontToBackWindowIDs: windowCache.windows.filter { !$0.isMinimized }.map(\.id),
                targetFrames: targetFrames,
                state: &state
            )
            focusedWindowSync = focusResult
            switch focusResult {
            case .switched:
                break
            case .alreadyActive, .noFocusedWindow, .unmanagedWindow:
                try visibilityCoordinator.applyVisibleSpaces(
                    state: &state,
                    targetFrames: targetFrames
                )
            }
        } else {
            focusedWindowSync = nil
            try visibilityCoordinator.applyVisibleSpaces(
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

    func isHiddenBySpace(_ id: WindowID) -> Bool {
        state.isHidden(id)
    }

    func spaceFrame(for id: WindowID) -> WindowFrame? {
        state.hiddenFrame(for: id) ?? windowCache.snapshot(for: id)?.frame
    }

    func systemFocusedWindowID() -> WindowID? {
        windowSystem.focusedWindowID()
    }

    func cachedFocusedWindowID() -> WindowID? {
        windowCache.focusedWindowID
    }

    func isSpaceVisible(_ space: String) -> Bool {
        guard let space = state.findSpace(space) else {
            return false
        }
        return state.visibleSpaces(
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        ).contains(space)
    }

    func effectiveMonitorSlot(for space: String) -> MonitorSlot {
        guard let space = state.findSpace(space) else {
            return 1
        }
        return state.monitorSlot(
            for: space,
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        )
    }

    func visibleSpace(on monitorSlot: MonitorSlot) -> String {
        state.visibleSpace(
            on: monitorSlot,
            availableMonitorSlots: windowCache.displayTopology.availableMonitorSlots
        ).rawValue
    }

    var displayTopology: DisplayTopologySnapshot {
        windowCache.displayTopology
    }

    func refreshDisplayTopology() throws {
        try displayCoordinator.refreshDisplayTopology()
    }

    @discardableResult
    func bootstrapWindowState() throws -> HiddenWindowRecordStartupApplyResult {
        let hiddenRecords = try applyHiddenWindowRecordsAtStartup()
        _ = try syncWindows()
        try visibilityCoordinator.applyVisibleSpaces(state: &state)
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

    func switchSpace(to space: String) throws -> SpaceSyncSummary? {
        guard let space = state.findSpace(space) else {
            return nil
        }
        return try switchExistingSpace(to: space)
    }

    private func switchExistingSpace(to space: SpaceID) throws -> SpaceSyncSummary {
        let sync = try syncWindows()
        try navigationCoordinator.switchSpace(
            to: space,
            frontToBackWindowIDs: windowCache.windows.filter { !$0.isMinimized }.map(\.id),
            state: &state
        )
        return sync
    }

    func moveFocusedWindow(to space: String) throws -> WindowMoveResult? {
        guard let space = state.findSpace(space) else {
            return nil
        }
        _ = try syncWindows()
        return try assignmentCoordinator.moveFocusedWindow(
            to: space,
            frontToBackWindowIDs: windows(in: currentSpace).map(\.id),
            state: &state
        )
    }

    @discardableResult
    func centerFocusedWindow() throws -> WindowID {
        _ = try syncWindows(reconcileVisibleWindowMonitorMembership: false)
        guard let id = windowSystem.focusedWindowID(), windowSystem.contains(id) else {
            throw SpaceError.noFocusedWindow
        }
        guard let frame = windowSystem.frame(for: id) else {
            throw SpaceError.frameUnavailable(id)
        }
        let displays = windowCache.displayTopology.displays
        guard let displayIndex = DisplayGeometry.index(
            containingOrNearest: frame.center,
            among: displays.map(\.frame)
        ) else {
            throw SpaceError.noDisplayAvailable
        }

        let visibleFrame = displays[displayIndex].visibleFrame
        let centeredFrame = WindowFrame(
            origin: CGPoint(
                x: visibleFrame.midX - frame.size.width / 2,
                y: visibleFrame.midY - frame.size.height / 2
            ),
            size: frame.size
        )
        try windowSystem.setPosition(centeredFrame.origin, for: id)
        windowCache.updateFrame(centeredFrame, for: id)
        return id
    }

    @discardableResult
    func applyConfig(_ config: CosmosConfig) throws -> SpaceSyncSummary {
        try applyConfigTransaction(config)
    }

    func focusWindow(_ id: WindowID) throws {
        guard windowSystem.contains(id) else {
            throw SpaceError.windowNotFound(id)
        }

        let space = state.membership(for: id) ?? state.currentSpace
        let availableMonitorSlots = windowCache.displayTopology.availableMonitorSlots
        let monitorSlot = state.monitorSlot(
            for: space,
            availableMonitorSlots: availableMonitorSlots
        )
        if space != state.visibleSpace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        ) {
            throw SpaceError.windowNotInVisibleSpace(id, space.rawValue)
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
    func shouldFollow(focusedWindowID: WindowID?, state: SpaceState) -> Bool {
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

private extension SpaceController {
    private func syncWindows(
        reconcileVisibleWindowMonitorMembership: Bool = true
    ) throws -> SpaceSyncSummary {
        try runtimeSynchronizer.synchronize(
            state: &state,
            reconcileVisibleWindowMonitorMembership: reconcileVisibleWindowMonitorMembership
        )
    }

    private func applyConfigTransaction(_ config: CosmosConfig) throws -> SpaceSyncSummary {
        let sync = try syncWindows()
        let previousState = state
        state.applyConfig(config)
        do {
            let mustSucceedWindowIDs = Set(state.assignedWindowIDs)
            let targetFrames = displayCoordinator.targetFramesForConfiguredMonitors(state: state)
            try visibilityCoordinator.applyVisibleSpaces(
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
