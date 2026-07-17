import Foundation

struct WorkspaceCatalog {
    private(set) var currentWorkspace: String
    private var workspaceOrder: [String]
    private var monitorSlotsByWorkspace: [String: MonitorSlot]
    private var visibleWorkspaceByMonitorSlot: [MonitorSlot: String]

    init(workspaces: [WorkspaceConfig]) {
        workspaceOrder = workspaces.map(\.name)
        currentWorkspace = workspaces[0].name
        monitorSlotsByWorkspace = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.name, $0.display) })
        visibleWorkspaceByMonitorSlot = [
            workspaces[0].display: workspaces[0].name
        ]
        seedVisibleWorkspaces()
    }

    var workspaces: [String] {
        workspaceOrder
    }

    func contains(_ workspace: String) -> Bool {
        workspaceOrder.contains(workspace)
    }

    mutating func apply(_ workspaces: [WorkspaceConfig]) {
        workspaceOrder = workspaces.map(\.name)
        monitorSlotsByWorkspace = Dictionary(uniqueKeysWithValues: workspaces.map { ($0.name, $0.display) })
        if !workspaceOrder.contains(currentWorkspace) {
            currentWorkspace = workspaceOrder[0]
        }
        pruneVisibleWorkspaces()
        visibleWorkspaceByMonitorSlot[monitorSlot(for: currentWorkspace)] = currentWorkspace
        seedVisibleWorkspaces()
    }

    mutating func activate(_ workspace: String) {
        currentWorkspace = workspace
        visibleWorkspaceByMonitorSlot[monitorSlot(for: workspace)] = workspace
    }

    func monitorSlot(for workspace: String) -> MonitorSlot {
        monitorSlotsByWorkspace[workspace] ?? 1
    }

    func effectiveMonitorSlot(
        for workspace: String,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> MonitorSlot {
        let homeSlot = monitorSlot(for: workspace)
        return availableMonitorSlots.contains(homeSlot) ? homeSlot : 1
    }

    func visibleWorkspace(
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> String {
        if effectiveMonitorSlot(
            for: currentWorkspace,
            availableMonitorSlots: availableMonitorSlots
        ) == monitorSlot {
            return currentWorkspace
        }

        return visibleWorkspaceByMonitorSlot[monitorSlot]
            ?? workspaceOrder.first {
                effectiveMonitorSlot(for: $0, availableMonitorSlots: availableMonitorSlots) == monitorSlot
            }
            ?? currentWorkspace
    }

    func visibleWorkspaces(availableMonitorSlots: Set<MonitorSlot>) -> Set<String> {
        guard !availableMonitorSlots.isEmpty else {
            return [currentWorkspace]
        }

        let currentSlot = effectiveMonitorSlot(
            for: currentWorkspace,
            availableMonitorSlots: availableMonitorSlots
        )
        var result: Set<String> = [currentWorkspace]
        for slot in availableMonitorSlots where slot != currentSlot {
            result.insert(visibleWorkspace(on: slot, availableMonitorSlots: availableMonitorSlots))
        }
        return result.intersection(workspaceOrder)
    }

    func nextWorkspace(
        after workspace: String,
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> String {
        let order = workspaceOrder.filter {
            effectiveMonitorSlot(for: $0, availableMonitorSlots: availableMonitorSlots) == monitorSlot
        }
        return cycledValue(in: order, after: workspace, direction: .forward)
            ?? visibleWorkspace(on: monitorSlot, availableMonitorSlots: availableMonitorSlots)
    }

    func previousWorkspace(
        before workspace: String,
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> String {
        let order = workspaceOrder.filter {
            effectiveMonitorSlot(for: $0, availableMonitorSlots: availableMonitorSlots) == monitorSlot
        }
        return cycledValue(in: order, after: workspace, direction: .backward)
            ?? visibleWorkspace(on: monitorSlot, availableMonitorSlots: availableMonitorSlots)
    }

    private mutating func seedVisibleWorkspaces() {
        for workspace in workspaceOrder {
            let slot = monitorSlot(for: workspace)
            if visibleWorkspaceByMonitorSlot[slot] == nil {
                visibleWorkspaceByMonitorSlot[slot] = workspace
            }
        }
    }

    private mutating func pruneVisibleWorkspaces() {
        visibleWorkspaceByMonitorSlot = visibleWorkspaceByMonitorSlot.reduce(into: [:]) { result, entry in
            if workspaceOrder.contains(entry.value), monitorSlot(for: entry.value) == entry.key {
                result[entry.key] = entry.value
            }
        }
    }
}
