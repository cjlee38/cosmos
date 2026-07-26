import Foundation

public struct SessionState: Codable, Equatable {
    public let currentSpace: SpaceID?
    public let visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID]
    public let hiddenWindows: [HiddenWindowRecord]

    public init(
        currentSpace: SpaceID? = nil,
        visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID] = [:],
        hiddenWindows: [HiddenWindowRecord] = []
    ) {
        self.currentSpace = currentSpace
        self.visibleSpaceByMonitorSlot = visibleSpaceByMonitorSlot
        self.hiddenWindows = hiddenWindows
    }
}

public protocol SessionStateStore: AnyObject {
    func load() throws -> SessionState?
    func updateSpaceState(
        currentSpace: SpaceID,
        visibleSpaceByMonitorSlot: [MonitorSlot: SpaceID]
    )
    func upsertRecord(_ record: HiddenWindowRecord)
    func removeRecord(windowID: WindowID, pid: pid_t?)
    func flushPendingWrites() throws
}
