import Foundation

struct SpaceState {
    private var catalog: SpaceCatalog
    private var memberships = SpaceMemberships()
    private var hiddenFrames = HiddenWindowFrameStore()

    init(config: CosmosConfig = .default, sessionState: SessionState? = nil) {
        catalog = SpaceCatalog(config: config, sessionState: sessionState)
    }

    var currentSpace: SpaceID {
        catalog.currentSpace
    }

    var currentConfig: CosmosConfig {
        catalog.config
    }

    var sessionState: SessionState {
        catalog.sessionState
    }

    var assignedWindowIDs: [WindowID] {
        memberships.assignedWindowIDs
    }

    var spaces: [SpaceID] {
        catalog.spaces
    }

    var spacesByRecency: [SpaceID] {
        catalog.spacesByRecency
    }

    func membership(for id: WindowID) -> SpaceID? {
        memberships.space(for: id)
    }

    func isHidden(_ id: WindowID) -> Bool {
        hiddenFrames.isHidden(id)
    }

    func hiddenFrame(for id: WindowID) -> WindowFrame? {
        hiddenFrames.frame(for: id)
    }

    var hiddenWindowIDs: [WindowID] {
        hiddenFrames.hiddenWindowIDs
    }

    func findSpace(_ space: String) -> SpaceID? {
        guard let space = SpaceID(rawValue: space) else {
            return nil
        }
        return catalog.contains(space) ? space : nil
    }

    func containsSpace(_ space: SpaceID) -> Bool {
        catalog.contains(space)
    }

    mutating func applyConfig(_ config: CosmosConfig) {
        catalog.apply(config)
        memberships.reassignInvalidSpaces(
            validSpaces: Set(config.spaces.map(\.id)),
            to: currentSpace
        )
    }

    mutating func prepareForRollback(to snapshot: SpaceState) {
        catalog = snapshot.catalog
        memberships = snapshot.memberships
        // Keep frames captured by the failed operation so its newly hidden windows
        // can be restored, then add frames for windows that were hidden before it.
        for id in snapshot.hiddenWindowIDs {
            if let frame = snapshot.hiddenFrame(for: id) {
                hiddenFrames.replace(frame, for: id)
            }
        }
    }

    mutating func activate(_ space: SpaceID) {
        catalog.activate(space)
    }

    func monitorSlot(
        for space: SpaceID,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> MonitorSlot {
        catalog.effectiveMonitorSlot(
            for: space,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func visibleSpace(
        on monitorSlot: MonitorSlot,
        availableMonitorSlots: Set<MonitorSlot>
    ) -> SpaceID {
        catalog.visibleSpace(
            on: monitorSlot,
            availableMonitorSlots: availableMonitorSlots
        )
    }

    func visibleSpaces(availableMonitorSlots: Set<MonitorSlot>) -> Set<SpaceID> {
        catalog.visibleSpaces(availableMonitorSlots: availableMonitorSlots)
    }

    mutating func assign(_ id: WindowID, to space: SpaceID) {
        memberships.assign(id, to: space)
    }

    mutating func storeHiddenFrameIfNeeded(_ frame: WindowFrame, for id: WindowID) {
        hiddenFrames.storeIfNeeded(frame, for: id)
    }

    mutating func replaceHiddenFrame(_ frame: WindowFrame, for id: WindowID) {
        hiddenFrames.replace(frame, for: id)
    }

    mutating func clearHiddenFrame(for id: WindowID) {
        hiddenFrames.clear(id)
    }

    func windowIDs(in space: SpaceID) -> [WindowID] {
        memberships.windowIDs(in: space)
    }

    mutating func removeWindow(_ id: WindowID) {
        memberships.remove(id)
        hiddenFrames.clear(id)
    }
}
