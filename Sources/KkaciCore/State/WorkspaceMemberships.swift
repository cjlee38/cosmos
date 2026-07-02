import Foundation

struct WorkspaceMemberships {
    private var windowIDsByWorkspace: [String: [WindowID]] = [:]

    var assignedWindowIDs: [WindowID] {
        windowIDsByWorkspace.values.flatMap { $0 }
    }

    var referencedWorkspaces: Set<String> {
        Set(windowIDsByWorkspace.keys)
    }

    func workspace(for id: WindowID) -> String? {
        windowIDsByWorkspace.first { _, ids in
            ids.contains(id)
        }?.key
    }

    mutating func assign(_ id: WindowID, to workspace: String) {
        remove(id)
        windowIDsByWorkspace[workspace, default: []].insert(id, at: 0)
    }

    mutating func unassign(_ id: WindowID) {
        remove(id)
    }

    mutating func capture(_ ids: [WindowID], into workspace: String) {
        for id in ids {
            remove(id)
            windowIDsByWorkspace[workspace, default: []].append(id)
        }
    }

    mutating func remove(_ id: WindowID) {
        for workspace in Array(windowIDsByWorkspace.keys) {
            windowIDsByWorkspace[workspace]?.removeAll { $0 == id }
            if windowIDsByWorkspace[workspace]?.isEmpty == true {
                windowIDsByWorkspace[workspace] = nil
            }
        }
    }

    mutating func recordFocus(_ id: WindowID, in workspace: String) {
        guard self.workspace(for: id) == workspace else {
            return
        }

        remove(id)
        windowIDsByWorkspace[workspace, default: []].insert(id, at: 0)
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        windowIDsByWorkspace[workspace] ?? []
    }

    func windowIDs(in workspace: String, currentFocused: WindowID?) -> [WindowID] {
        guard let currentFocused, self.workspace(for: currentFocused) == workspace else {
            return windowIDs(in: workspace)
        }

        return [currentFocused] + windowIDs(in: workspace).filter { $0 != currentFocused }
    }
}
