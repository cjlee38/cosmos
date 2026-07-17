import Foundation

struct WorkspaceState {
    private var catalog: WorkspaceCatalog
    private var memberships = WorkspaceMemberships()
    private var liveWindows = LiveWindowSetTracker()
    private var hiddenFrames = HiddenWindowFrameStore()

    init(workspaces: [WorkspaceConfig] = KkaciConfig.default.workspaces) {
        catalog = WorkspaceCatalog(workspaces: workspaces)
    }

    var currentWorkspace: String {
        catalog.currentWorkspace
    }

    var assignedWindowIDs: [WindowID] {
        memberships.assignedWindowIDs
    }

    var workspaces: [String] {
        catalog.workspaces
    }

    mutating func sync(
        windows: [WindowSnapshot],
        availableMonitorSlots: Set<MonitorSlot> = [1],
        reconcileVisibleWindowMonitorMembership: Bool = true,
        monitorSlotForFrame: (WindowFrame?) -> MonitorSlot
    ) -> WorkspaceSyncSummary {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let aliveWindowIDs = Set(windowsByID.keys)
        let diff = liveWindows.sync(aliveWindowIDs: aliveWindowIDs)

        for id in diff.new {
            let monitorSlot = monitorSlotForFrame(windowsByID[id]?.frame)
            memberships.assign(
                id,
                to: visibleWorkspace(on: monitorSlot, availableMonitorSlots: availableMonitorSlots)
            )
        }

        if reconcileVisibleWindowMonitorMembership {
            reconcileVisibleWindowMemberships(
                windows,
                availableMonitorSlots: availableMonitorSlots,
                monitorSlotForFrame: monitorSlotForFrame
            )
        }

        for id in diff.removed {
            removeWindow(id)
        }

        return WorkspaceSyncSummary(
            autoAssigned: diff.new.map { id in
                let monitorSlot = monitorSlotForFrame(windowsByID[id]?.frame)
                return (
                    id,
                    visibleWorkspace(on: monitorSlot, availableMonitorSlots: availableMonitorSlots)
                )
            },
            removed: diff.removed
        )
    }

    private mutating func reconcileVisibleWindowMemberships(
        _ windows: [WindowSnapshot],
        availableMonitorSlots: Set<MonitorSlot>,
        monitorSlotForFrame: (WindowFrame?) -> MonitorSlot
    ) {
        for window in windows where !window.isMinimized && !isHidden(window.id) {
            guard let workspace = membership(for: window.id),
                  let frame = window.frame
            else {
                continue
            }

            let currentSlot = monitorSlotForFrame(frame)
            if monitorSlot(for: workspace, availableMonitorSlots: availableMonitorSlots) != currentSlot {
                memberships.assign(
                    window.id,
                    to: visibleWorkspace(on: currentSlot, availableMonitorSlots: availableMonitorSlots)
                )
            }
        }
    }

    func membership(for id: WindowID) -> String? {
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

    func containsWorkspace(_ workspace: String) -> Bool {
        catalog.contains(workspace)
    }

    func findWorkspace(_ workspace: String) -> String? {
        let workspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        return catalog.contains(workspace) ? workspace : nil
    }

    mutating func applyWorkspaces(_ workspaces: [WorkspaceConfig]) {
        catalog.apply(workspaces)
        memberships.reassignInvalidWorkspaces(
            validWorkspaces: Set(workspaces.map(\.name)),
            to: currentWorkspace
        )
    }

    mutating func restoreWorkspaceConfiguration(from snapshot: WorkspaceState) {
        catalog = snapshot.catalog
        memberships = snapshot.memberships
    }

    mutating func restoreLogicalState(from snapshot: WorkspaceState) {
        catalog = snapshot.catalog
        memberships = snapshot.memberships
        liveWindows = snapshot.liveWindows
        for id in snapshot.hiddenWindowIDs {
            if let frame = snapshot.hiddenFrame(for: id) {
                hiddenFrames.replace(frame, for: id)
            }
        }
    }

    mutating func activate(_ workspace: String) {
        catalog.activate(workspace)
    }

    func configuredMonitorSlot(for workspace: String) -> MonitorSlot {
        catalog.monitorSlot(for: workspace)
    }

    func monitorSlot(
        for workspace: String,
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
    ) -> String {
        catalog.visibleWorkspace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func visibleWorkspaces(availableMonitorSlots: Set<MonitorSlot>) -> Set<String> {
        catalog.visibleWorkspaces(availableMonitorSlots: availableMonitorSlots)
    }

    mutating func assign(_ id: WindowID, to workspace: String) {
        memberships.assign(id, to: workspace)
    }

    mutating func capture(_ ids: [WindowID], into workspace: String) {
        memberships.capture(ids, into: workspace)
        liveWindows.recordKnown(ids)
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

    func nextWorkspace(
        after workspace: String,
        availableMonitorSlots: Set<MonitorSlot> = [1]
    ) -> String {
        let monitorSlot = monitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
        return catalog.nextWorkspace(
            after: workspace,
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func previousWorkspace(
        before workspace: String,
        availableMonitorSlots: Set<MonitorSlot> = [1]
    ) -> String {
        let monitorSlot = monitorSlot(
            for: workspace,
            availableMonitorSlots: availableMonitorSlots
        )
        return catalog.previousWorkspace(
            before: workspace,
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        memberships.windowIDs(in: workspace)
    }

    private mutating func removeWindow(_ id: WindowID) {
        memberships.remove(id)
        hiddenFrames.clear(id)
    }
}
