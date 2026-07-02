import Foundation

struct WorkspaceState {
    private var catalog: WorkspaceCatalog
    private var memberships = WorkspaceMemberships()
    private var liveWindows = LiveWindowSetTracker()
    private var hiddenFrames = HiddenWindowFrameStore()

    init(workspaces: WorkspaceConfig = WorkspaceConfig(names: ["1", "2", "3"])) {
        self.catalog = WorkspaceCatalog(workspaces: workspaces)
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

    mutating func sync(aliveWindowIDs: Set<WindowID>) -> WorkspaceSyncSummary {
        let diff = liveWindows.sync(aliveWindowIDs: aliveWindowIDs)

        for id in diff.new {
            memberships.assign(id, to: activeWorkspace)
        }

        for id in diff.removed {
            removeWindow(id)
        }

        return WorkspaceSyncSummary(
            autoAssigned: diff.new.map { ($0, activeWorkspace) },
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

    mutating func addWorkspace(_ workspace: String) {
        catalog.add(workspace)
    }

    mutating func applyWorkspaces(_ workspaces: WorkspaceConfig) {
        let referencedWorkspaces = memberships.referencedWorkspaces
            .union([activeWorkspace])
        catalog.apply(workspaces, keeping: referencedWorkspaces)
    }

    mutating func activate(_ workspace: String) {
        catalog.activate(workspace)
    }

    mutating func assign(_ id: WindowID, to workspace: String) {
        memberships.assign(id, to: workspace)
    }

    mutating func unassign(_ id: WindowID) {
        memberships.unassign(id)
    }

    mutating func capture(_ ids: [WindowID], into workspace: String) {
        memberships.capture(ids, into: workspace)
        liveWindows.recordKnown(ids)
    }

    mutating func storeHiddenFrameIfNeeded(_ frame: WindowFrame, for id: WindowID) {
        hiddenFrames.storeIfNeeded(frame, for: id)
    }

    mutating func clearHiddenFrame(for id: WindowID) {
        hiddenFrames.clear(id)
    }

    mutating func recordFocus(_ id: WindowID, in workspace: String) {
        memberships.recordFocus(id, in: workspace)
    }

    func focusTarget(for workspace: String, fallback: WindowID?) -> WindowID? {
        windowIDs(in: workspace).first ?? fallback
    }

    func nextWorkspace(after workspace: String) -> String {
        catalog.nextWorkspace(after: workspace)
    }

    func previousWorkspace(before workspace: String) -> String {
        catalog.previousWorkspace(before: workspace)
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        memberships.windowIDs(in: workspace)
    }

    func windowIDsByMostRecentFocus(in workspace: String, currentFocused: WindowID? = nil) -> [WindowID] {
        memberships.windowIDs(in: workspace, currentFocused: currentFocused)
    }

    func nextWindow(in workspace: String, after id: WindowID?) -> WindowID? {
        cycledValue(in: windowIDsByMostRecentFocus(in: workspace), after: id, direction: .forward)
    }

    func previousWindow(in workspace: String, before id: WindowID?) -> WindowID? {
        cycledValue(in: windowIDsByMostRecentFocus(in: workspace), after: id, direction: .backward)
    }

    private mutating func removeWindow(_ id: WindowID) {
        memberships.remove(id)
        hiddenFrames.clear(id)
    }
}
