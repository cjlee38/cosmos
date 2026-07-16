import Foundation

struct WorkspaceMemberships {
    private var workspaceByWindowID: [WindowID: String] = [:]

    var assignedWindowIDs: [WindowID] {
        Array(workspaceByWindowID.keys)
    }

    func workspace(for id: WindowID) -> String? {
        workspaceByWindowID[id]
    }

    mutating func assign(_ id: WindowID, to workspace: String) {
        workspaceByWindowID[id] = workspace
    }

    mutating func capture(_ ids: [WindowID], into workspace: String) {
        for id in ids {
            workspaceByWindowID[id] = workspace
        }
    }

    mutating func remove(_ id: WindowID) {
        workspaceByWindowID[id] = nil
    }

    mutating func reassignInvalidWorkspaces(validWorkspaces: Set<String>, to workspace: String) {
        for (id, assignedWorkspace) in workspaceByWindowID where !validWorkspaces.contains(assignedWorkspace) {
            workspaceByWindowID[id] = workspace
        }
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        workspaceByWindowID.compactMap { id, assignedWorkspace in
            assignedWorkspace == workspace ? id : nil
        }
    }
}
