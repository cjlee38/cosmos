import Foundation

struct WorkspaceCatalog {
    private(set) var activeWorkspace: String
    private var workspaceOrder: [String]
    private var monitorSlotsByWorkspace: [String: MonitorSlot]
    private var activeWorkspaceByMonitorSlot: [MonitorSlot: String]

    init(workspaces: WorkspaceConfig) {
        workspaceOrder = workspaces.names
        activeWorkspace = workspaces.names[0]
        monitorSlotsByWorkspace = workspaces.monitorSlotsByName
        activeWorkspaceByMonitorSlot = [
            workspaces.monitorSlot(for: workspaces.names[0]): workspaces.names[0]
        ]
        seedActiveWorkspaces()
    }

    var workspaces: [String] {
        workspaceOrder
    }

    func contains(_ workspace: String) -> Bool {
        workspaceOrder.contains(workspace)
    }

    mutating func apply(_ workspaces: WorkspaceConfig) {
        workspaceOrder = workspaces.names
        monitorSlotsByWorkspace = workspaces.monitorSlotsByName
        if !workspaceOrder.contains(activeWorkspace) {
            activeWorkspace = workspaceOrder[0]
        }
        pruneActiveWorkspaces()
        activeWorkspaceByMonitorSlot[monitorSlot(for: activeWorkspace)] = activeWorkspace
        seedActiveWorkspaces()
    }

    mutating func activate(_ workspace: String) {
        activeWorkspace = workspace
        activeWorkspaceByMonitorSlot[monitorSlot(for: workspace)] = workspace
    }

    var workspaceConfig: WorkspaceConfig {
        WorkspaceConfig(names: workspaceOrder, monitorSlotsByName: monitorSlotsByWorkspace)
    }

    func monitorSlot(for workspace: String) -> MonitorSlot {
        monitorSlotsByWorkspace[workspace] ?? 1
    }

    func activeWorkspace(on monitorSlot: MonitorSlot) -> String {
        activeWorkspaceByMonitorSlot[monitorSlot]
            ?? workspaceOrder.first { self.monitorSlot(for: $0) == monitorSlot }
            ?? activeWorkspace
    }

    var activeWorkspaces: Set<String> {
        Set(activeWorkspaceByMonitorSlot.values).intersection(workspaceOrder)
    }

    func nextWorkspace(after workspace: String, on monitorSlot: MonitorSlot) -> String {
        let order = workspaceOrder.filter { self.monitorSlot(for: $0) == monitorSlot }
        return cycledValue(in: order, after: workspace, direction: .forward) ?? activeWorkspace(on: monitorSlot)
    }

    func previousWorkspace(before workspace: String, on monitorSlot: MonitorSlot) -> String {
        let order = workspaceOrder.filter { self.monitorSlot(for: $0) == monitorSlot }
        return cycledValue(in: order, after: workspace, direction: .backward) ?? activeWorkspace(on: monitorSlot)
    }

    private mutating func seedActiveWorkspaces() {
        for workspace in workspaceOrder {
            let slot = monitorSlot(for: workspace)
            if activeWorkspaceByMonitorSlot[slot] == nil {
                activeWorkspaceByMonitorSlot[slot] = workspace
            }
        }
    }

    private mutating func pruneActiveWorkspaces() {
        activeWorkspaceByMonitorSlot = activeWorkspaceByMonitorSlot.reduce(into: [:]) { result, entry in
            if workspaceOrder.contains(entry.value), monitorSlot(for: entry.value) == entry.key {
                result[entry.key] = entry.value
            }
        }
    }
}
