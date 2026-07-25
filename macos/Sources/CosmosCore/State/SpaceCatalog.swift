import Foundation

struct SpaceCatalog {
    private(set) var config: CosmosConfig
    private(set) var currentSpace: SpaceID
    private var visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID]
    private(set) var spacesByRecency: [SpaceID]

    init(config: CosmosConfig) {
        self.config = config
        currentSpace = config.spaces[0].id
        spacesByRecency = config.spaces.map(\.id)
        visibleSpaceByMonitorSlot = [
            config.spaces[0].display: config.spaces[0].id
        ]
        seedVisibleSpaces()
    }

    var spaces: [SpaceID] {
        config.spaces.map(\.id)
    }

    func contains(_ space: SpaceID) -> Bool {
        config.spaces.contains { $0.id == space }
    }

    mutating func apply(_ config: CosmosConfig) {
        self.config = config
        if !contains(currentSpace) {
            currentSpace = config.spaces[0].id
        }
        let validSpaces = Set(spaces)
        spacesByRecency.removeAll { !validSpaces.contains($0) }
        var recentSpaces = Set(spacesByRecency)
        for space in spaces where recentSpaces.insert(space).inserted {
            spacesByRecency.append(space)
        }
        recordActivation(of: currentSpace)
        pruneVisibleSpaces()
        visibleSpaceByMonitorSlot[monitorSlot(for: currentSpace)] = currentSpace
        seedVisibleSpaces()
    }

    mutating func activate(_ space: SpaceID) {
        currentSpace = space
        recordActivation(of: space)
        visibleSpaceByMonitorSlot[monitorSlot(for: space)] = space
    }

    func monitorSlot(for space: SpaceID) -> MonitorSlot {
        config.spaces.first { $0.id == space }?.display ?? 1
    }

    func effectiveMonitorSlot(
        for space: SpaceID,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> MonitorSlot {
        let homeSlot = monitorSlot(for: space)
        return availableMonitorSlots.contains(homeSlot) ? homeSlot : 1
    }

    func visibleSpace(
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> SpaceID {
        if effectiveMonitorSlot(
            for: currentSpace,
            availableMonitorSlots: availableMonitorSlots
        ) == monitorSlot {
            return currentSpace
        }

        return visibleSpaceByMonitorSlot[monitorSlot]
            ?? spaces.first {
                effectiveMonitorSlot(for: $0, availableMonitorSlots: availableMonitorSlots) == monitorSlot
            }
            ?? currentSpace
    }

    func visibleSpaces(availableMonitorSlots: Set<MonitorSlot>) -> Set<SpaceID> {
        guard !availableMonitorSlots.isEmpty else {
            return [currentSpace]
        }

        let currentSlot = effectiveMonitorSlot(
            for: currentSpace,
            availableMonitorSlots: availableMonitorSlots
        )
        var result: Set<SpaceID> = [currentSpace]
        for slot in availableMonitorSlots where slot != currentSlot {
            result.insert(visibleSpace(on: slot, availableMonitorSlots: availableMonitorSlots))
        }
        return result.intersection(spaces)
    }

    private mutating func seedVisibleSpaces() {
        for space in spaces {
            let slot = monitorSlot(for: space)
            if visibleSpaceByMonitorSlot[slot] == nil {
                visibleSpaceByMonitorSlot[slot] = space
            }
        }
    }

    private mutating func pruneVisibleSpaces() {
        visibleSpaceByMonitorSlot = visibleSpaceByMonitorSlot.reduce(into: [:]) { result, entry in
            if contains(entry.value), monitorSlot(for: entry.value) == entry.key {
                result[entry.key] = entry.value
            }
        }
    }

    private mutating func recordActivation(of space: SpaceID) {
        spacesByRecency.removeAll { $0 == space }
        spacesByRecency.insert(space, at: 0)
    }
}
