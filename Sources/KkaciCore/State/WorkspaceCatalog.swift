import Foundation

struct WorkspaceCatalog {
    private(set) var config: KkaciConfig
    private(set) var currentWorkspace: WorkspaceID
    private var visibleWorkspaceByMonitorSlot: [MonitorSlot: WorkspaceID]
    private(set) var workspacesByRecency: [WorkspaceID]

    init(config: KkaciConfig) {
        self.config = config
        currentWorkspace = config.workspaces[0].id
        workspacesByRecency = config.workspaces.map(\.id)
        visibleWorkspaceByMonitorSlot = [
            config.workspaces[0].display: config.workspaces[0].id
        ]
        seedVisibleWorkspaces()
    }

    var workspaces: [WorkspaceID] {
        config.workspaces.map(\.id)
    }

    func contains(_ workspace: WorkspaceID) -> Bool {
        config.workspaces.contains { $0.id == workspace }
    }

    mutating func apply(_ config: KkaciConfig) {
        self.config = config
        if !contains(currentWorkspace) {
            currentWorkspace = config.workspaces[0].id
        }
        let validWorkspaces = Set(workspaces)
        workspacesByRecency.removeAll { !validWorkspaces.contains($0) }
        var recentWorkspaces = Set(workspacesByRecency)
        for workspace in workspaces where recentWorkspaces.insert(workspace).inserted {
            workspacesByRecency.append(workspace)
        }
        recordActivation(of: currentWorkspace)
        pruneVisibleWorkspaces()
        visibleWorkspaceByMonitorSlot[monitorSlot(for: currentWorkspace)] = currentWorkspace
        seedVisibleWorkspaces()
    }

    mutating func activate(_ workspace: WorkspaceID) {
        currentWorkspace = workspace
        recordActivation(of: workspace)
        visibleWorkspaceByMonitorSlot[monitorSlot(for: workspace)] = workspace
    }

    func monitorSlot(for workspace: WorkspaceID) -> MonitorSlot {
        config.workspaces.first { $0.id == workspace }?.display ?? 1
    }

    func effectiveMonitorSlot(
        for workspace: WorkspaceID,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> MonitorSlot {
        let homeSlot = monitorSlot(for: workspace)
        return availableMonitorSlots.contains(homeSlot) ? homeSlot : 1
    }

    func visibleWorkspace(
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> WorkspaceID {
        if effectiveMonitorSlot(
            for: currentWorkspace,
            availableMonitorSlots: availableMonitorSlots
        ) == monitorSlot {
            return currentWorkspace
        }

        return visibleWorkspaceByMonitorSlot[monitorSlot]
            ?? workspaces.first {
                effectiveMonitorSlot(for: $0, availableMonitorSlots: availableMonitorSlots) == monitorSlot
            }
            ?? currentWorkspace
    }

    func visibleWorkspaces(availableMonitorSlots: Set<MonitorSlot>) -> Set<WorkspaceID> {
        guard !availableMonitorSlots.isEmpty else {
            return [currentWorkspace]
        }

        let currentSlot = effectiveMonitorSlot(
            for: currentWorkspace,
            availableMonitorSlots: availableMonitorSlots
        )
        var result: Set<WorkspaceID> = [currentWorkspace]
        for slot in availableMonitorSlots where slot != currentSlot {
            result.insert(visibleWorkspace(on: slot, availableMonitorSlots: availableMonitorSlots))
        }
        return result.intersection(workspaces)
    }

    private mutating func seedVisibleWorkspaces() {
        for workspace in workspaces {
            let slot = monitorSlot(for: workspace)
            if visibleWorkspaceByMonitorSlot[slot] == nil {
                visibleWorkspaceByMonitorSlot[slot] = workspace
            }
        }
    }

    private mutating func pruneVisibleWorkspaces() {
        visibleWorkspaceByMonitorSlot = visibleWorkspaceByMonitorSlot.reduce(into: [:]) { result, entry in
            if contains(entry.value), monitorSlot(for: entry.value) == entry.key {
                result[entry.key] = entry.value
            }
        }
    }

    private mutating func recordActivation(of workspace: WorkspaceID) {
        workspacesByRecency.removeAll { $0 == workspace }
        workspacesByRecency.insert(workspace, at: 0)
    }
}
