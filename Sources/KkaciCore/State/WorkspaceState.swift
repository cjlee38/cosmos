import Foundation

struct WorkspaceState {
    private var catalog: WorkspaceCatalog
    private var memberships = WorkspaceMemberships()
    private var liveWindows = LiveWindowSetTracker()
    private var hiddenFrames = HiddenWindowFrameStore()

    init(workspaces: WorkspaceConfig = WorkspaceConfig(names: ["1", "2", "3"])) {
        catalog = WorkspaceCatalog(workspaces: workspaces)
    }

    var activeWorkspace: String {
        catalog.activeWorkspace
    }

    var assignedWindowIDs: [WindowID] {
        memberships.assignedWindowIDs
    }

    var workspaces: [String] {
        catalog.workspaces
    }

    var workspaceConfig: WorkspaceConfig {
        catalog.workspaceConfig
    }

    var activeWorkspaces: Set<String> {
        catalog.activeWorkspaces
    }

    mutating func sync(
        windows: [WindowSnapshot],
        monitorSlotForFrame: (WindowFrame?) -> MonitorSlot
    ) -> WorkspaceSyncSummary {
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let aliveWindowIDs = Set(windowsByID.keys)
        let diff = liveWindows.sync(aliveWindowIDs: aliveWindowIDs)

        for id in diff.new {
            let monitorSlot = monitorSlotForFrame(windowsByID[id]?.frame)
            memberships.assign(id, to: activeWorkspace(on: monitorSlot))
        }

        for window in windows where !window.isMinimized && !isHidden(window.id) {
            guard let workspace = membership(for: window.id),
                  let frame = window.frame
            else {
                continue
            }

            let currentSlot = monitorSlotForFrame(frame)
            if monitorSlot(for: workspace) != currentSlot {
                memberships.assign(window.id, to: activeWorkspace(on: currentSlot))
            }
        }

        for id in diff.removed {
            removeWindow(id)
        }

        return WorkspaceSyncSummary(
            autoAssigned: diff.new.map { id in
                let monitorSlot = monitorSlotForFrame(windowsByID[id]?.frame)
                return (id, activeWorkspace(on: monitorSlot))
            },
            removed: diff.removed
        )
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

    mutating func addWorkspace(_ workspace: String, monitorSlot: MonitorSlot = 1) {
        catalog.add(workspace, monitorSlot: monitorSlot)
    }

    mutating func applyWorkspaces(_ workspaces: WorkspaceConfig) {
        let referencedWorkspaces = memberships.referencedWorkspaces
            .union(activeWorkspaces)
            .union([activeWorkspace])
        catalog.apply(workspaces, keeping: referencedWorkspaces)
    }

    mutating func restoreWorkspaceCatalog(from snapshot: WorkspaceState) {
        catalog = snapshot.catalog
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

    func monitorSlot(for workspace: String) -> MonitorSlot {
        catalog.monitorSlot(for: workspace)
    }

    func activeWorkspace(on monitorSlot: MonitorSlot) -> String {
        catalog.activeWorkspace(on: monitorSlot)
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

    func nextWorkspace(after workspace: String) -> String {
        catalog.nextWorkspace(after: workspace, on: monitorSlot(for: workspace))
    }

    func previousWorkspace(before workspace: String) -> String {
        catalog.previousWorkspace(before: workspace, on: monitorSlot(for: workspace))
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        memberships.windowIDs(in: workspace)
    }

    private mutating func removeWindow(_ id: WindowID) {
        memberships.remove(id)
        hiddenFrames.clear(id)
    }
}
