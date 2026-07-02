import Foundation

struct WorkspaceMemberships {
    private var memberships: [WindowID: String] = [:]

    var assignedWindowIDs: [WindowID] {
        Array(memberships.keys)
    }

    var referencedWorkspaces: Set<String> {
        Set(memberships.values)
    }

    func workspace(for id: WindowID) -> String? {
        memberships[id]
    }

    mutating func assign(_ id: WindowID, to workspace: String) {
        memberships[id] = workspace
    }

    mutating func unassign(_ id: WindowID) {
        memberships[id] = nil
    }

    mutating func capture(_ ids: [WindowID], into workspace: String) {
        for id in ids {
            memberships[id] = workspace
        }
    }

    mutating func remove(_ id: WindowID) {
        memberships[id] = nil
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        memberships
            .filter { $0.value == workspace }
            .map(\.key)
            .sorted()
    }
}
