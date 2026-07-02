import Foundation

struct WorkspaceCatalog {
    private(set) var activeWorkspace: String
    private var workspaceOrder: [String]

    init(workspaces: WorkspaceConfig) {
        self.workspaceOrder = workspaces.names
        self.activeWorkspace = workspaces.names[0]
    }

    var workspaces: [String] {
        workspaceOrder
    }

    func contains(_ workspace: String) -> Bool {
        workspaceOrder.contains(workspace)
    }

    mutating func add(_ workspace: String) {
        if !workspaceOrder.contains(workspace) {
            workspaceOrder.append(workspace)
        }
    }

    mutating func apply(_ workspaces: WorkspaceConfig, keeping referencedWorkspaces: Set<String>) {
        var nextOrder = workspaces.names
        for workspace in workspaceOrder where referencedWorkspaces.contains(workspace) {
            if !nextOrder.contains(workspace) {
                nextOrder.append(workspace)
            }
        }

        workspaceOrder = nextOrder
        if !workspaceOrder.contains(activeWorkspace) {
            activeWorkspace = workspaceOrder[0]
        }
    }

    mutating func activate(_ workspace: String) {
        activeWorkspace = workspace
    }

    func nextWorkspace(after workspace: String) -> String {
        cycledValue(in: workspaceOrder, after: workspace, direction: .forward) ?? activeWorkspace
    }

    func previousWorkspace(before workspace: String) -> String {
        cycledValue(in: workspaceOrder, after: workspace, direction: .backward) ?? activeWorkspace
    }
}
