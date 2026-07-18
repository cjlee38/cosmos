import CoreGraphics
import Foundation

public struct HiddenWindowRecord: Codable, Equatable {
    public let windowID: WindowID
    public let pid: pid_t
    public let workspace: WorkspaceID
    public let originalFrame: WindowFrame
    public let hiddenPosition: CGPoint

    public init(
        windowID: WindowID,
        pid: pid_t,
        workspace: WorkspaceID,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint
    ) {
        self.windowID = windowID
        self.pid = pid
        self.workspace = workspace
        self.originalFrame = originalFrame
        self.hiddenPosition = hiddenPosition
    }
}

public protocol HiddenWindowRecordStore: AnyObject {
    func loadRecords() throws -> [HiddenWindowRecord]
    func upsertRecord(_ record: HiddenWindowRecord)
    func removeRecord(windowID: WindowID, pid: pid_t?)
    func flushPendingWrites() throws
}
