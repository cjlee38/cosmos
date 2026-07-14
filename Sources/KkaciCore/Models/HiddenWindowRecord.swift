import CoreGraphics
import Foundation

public struct HiddenWindowRecord: Codable, Equatable {
    public let windowID: WindowID
    public let pid: pid_t
    public let workspace: String
    public let originalFrame: WindowFrame
    public let hiddenPosition: CGPoint
    public let updatedAt: Date

    public init(
        windowID: WindowID,
        pid: pid_t,
        workspace: String,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint,
        updatedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.pid = pid
        self.workspace = workspace
        self.originalFrame = originalFrame
        self.hiddenPosition = hiddenPosition
        self.updatedAt = updatedAt
    }
}

public protocol HiddenWindowRecordStore: AnyObject {
    func loadRecords() throws -> [HiddenWindowRecord]
    func upsertRecord(_ record: HiddenWindowRecord)
    func removeRecord(windowID: WindowID, pid: pid_t?)
    func flushPendingWrites() throws
}
