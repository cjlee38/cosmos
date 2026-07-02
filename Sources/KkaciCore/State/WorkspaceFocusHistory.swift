import Foundation

struct WorkspaceFocusHistory {
    private var lastFocusedByWorkspace: [String: WindowID] = [:]

    var referencedWorkspaces: Set<String> {
        Set(lastFocusedByWorkspace.keys)
    }

    mutating func record(_ id: WindowID, in workspace: String) {
        lastFocusedByWorkspace[workspace] = id
    }

    mutating func clear(_ id: WindowID, in workspace: String) {
        if lastFocusedByWorkspace[workspace] == id {
            lastFocusedByWorkspace[workspace] = nil
        }
    }

    mutating func remove(_ id: WindowID) {
        for (workspace, windowID) in lastFocusedByWorkspace where windowID == id {
            lastFocusedByWorkspace[workspace] = nil
        }
    }

    func target(for workspace: String, fallback: WindowID?) -> WindowID? {
        lastFocusedByWorkspace[workspace] ?? fallback
    }
}
