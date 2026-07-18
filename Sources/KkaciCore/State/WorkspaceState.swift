import Foundation

struct WorkspaceState {
    private var catalog: WorkspaceCatalog
    private var memberships = WorkspaceMemberships()
    private var hiddenFrames = HiddenWindowFrameStore()

    init(config: KkaciConfig = .default) {
        catalog = WorkspaceCatalog(config: config)
    }

    var currentWorkspace: WorkspaceID {
        catalog.currentWorkspace
    }

    var currentConfig: KkaciConfig {
        catalog.config
    }

    var assignedWindowIDs: [WindowID] {
        memberships.assignedWindowIDs
    }

    var workspaces: [WorkspaceID] {
        catalog.workspaces
    }

    func membership(for id: WindowID) -> WorkspaceID? {
        memberships.workspace(for: id)
    }

    func isHidden(_ id: WindowID) -> Bool {
        hiddenFrames.isHidden(id)
    }

    func hiddenFrame(for id: WindowID) -> WindowFrame? {
        hiddenFrames.frame(for: id)
    }

    var hiddenWindowIDs: [WindowID] {
        hiddenFrames.hiddenWindowIDs
    }

    func findWorkspace(_ workspace: String) -> WorkspaceID? {
        guard let workspace = WorkspaceID(rawValue: workspace) else {
            return nil
        }
        return catalog.contains(workspace) ? workspace : nil
    }

    func containsWorkspace(_ workspace: WorkspaceID) -> Bool {
        catalog.contains(workspace)
    }

    mutating func applyConfig(_ config: KkaciConfig) {
        catalog.apply(config)
        memberships.reassignInvalidWorkspaces(
            validWorkspaces: Set(config.workspaces.map(\.id)),
            to: currentWorkspace
        )
    }

    mutating func prepareForRollback(to snapshot: WorkspaceState) {
        catalog = snapshot.catalog
        memberships = snapshot.memberships
        // Keep frames captured by the failed operation so its newly hidden windows
        // can be restored, then add frames for windows that were hidden before it.
        for id in snapshot.hiddenWindowIDs {
            if let frame = snapshot.hiddenFrame(for: id) {
                hiddenFrames.replace(frame, for: id)
            }
        }
    }

    mutating func activate(_ workspace: WorkspaceID) {
        catalog.activate(workspace)
    }

    func monitorSlot(
        for workspace: WorkspaceID,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> MonitorSlot {
        catalog.effectiveMonitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func visibleWorkspace(
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> WorkspaceID {
        catalog.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func visibleWorkspaces(availableMonitorSlots: Set<MonitorSlot>) -> Set<WorkspaceID> {
        catalog.visibleWorkspaces(availableMonitorSlots: availableMonitorSlots)
    }

    mutating func assign(_ id: WindowID, to workspace: WorkspaceID) {
        memberships.assign(id, to: workspace)
    }

    mutating func storeHiddenFrameIfNeeded(_ frame: WindowFrame, for id: WindowID) {
        hiddenFrames.storeIfNeeded(frame, for: id)
    }

    mutating func replaceHiddenFrame(_ frame: WindowFrame, for id: WindowID) {
        hiddenFrames.replace(frame, for: id)
    }

    mutating func clearHiddenFrame(for id: WindowID) {
        hiddenFrames.clear(id)
    }

    func windowIDs(in workspace: WorkspaceID) -> [WindowID] {
        memberships.windowIDs(in: workspace)
    }

    mutating func removeWindow(_ id: WindowID) {
        memberships.remove(id)
        hiddenFrames.clear(id)
    }
}
