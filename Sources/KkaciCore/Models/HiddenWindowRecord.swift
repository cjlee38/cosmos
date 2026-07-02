import CoreGraphics
import Foundation

public struct HiddenWindowRecord: Codable, Equatable {
    public let windowID: WindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public let title: String
    public let workspace: String
    public let originalFrame: WindowFrame
    public let hiddenPosition: CGPoint
    public let updatedAt: Date

    public init(
        windowID: WindowID,
        pid: pid_t,
        bundleID: String?,
        appName: String,
        title: String,
        workspace: String,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint,
        updatedAt: Date = Date()
    ) {
        self.windowID = windowID
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
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
    func flushPendingWrites()
}
