import Foundation

struct WorkspaceMemberships {
    private var workspaceByWindowID: [WindowID: WorkspaceID] = [:]

    var assignedWindowIDs: [WindowID] {
        Array(workspaceByWindowID.keys)
    }

    func workspace(for id: WindowID) -> WorkspaceID? {
        workspaceByWindowID[id]
    }

    mutating func assign(_ id: WindowID, to workspace: WorkspaceID) {
        workspaceByWindowID[id] = workspace
    }

    mutating func remove(_ id: WindowID) {
        workspaceByWindowID[id] = nil
    }

    mutating func reassignInvalidWorkspaces(validWorkspaces: Set<WorkspaceID>, to workspace: WorkspaceID) {
        for (id, assignedWorkspace) in workspaceByWindowID where !validWorkspaces.contains(assignedWorkspace) {
            workspaceByWindowID[id] = workspace
        }
    }

    func windowIDs(in workspace: WorkspaceID) -> [WindowID] {
        workspaceByWindowID.compactMap { id, assignedWorkspace in
            assignedWorkspace == workspace ? id : nil
        }
    }
}
