import Foundation

public struct HiddenWindowRecordAssignment: Equatable {
    public let windowID: WindowID
    public let workspace: String

    public init(windowID: WindowID, workspace: String) {
        self.windowID = windowID
        self.workspace = workspace
    }
}

public struct HiddenWindowRecordStartupApplyResult: Equatable {
    public static let empty = HiddenWindowRecordStartupApplyResult(restored: [], reassigned: [], ignored: [])

    public let restored: [WindowID]
    public let reassigned: [HiddenWindowRecordAssignment]
    public let ignored: [HiddenWindowRecord]

    public init(restored: [WindowID], reassigned: [HiddenWindowRecordAssignment], ignored: [HiddenWindowRecord]) {
        self.restored = restored
        self.reassigned = reassigned
        self.ignored = ignored
    }

    public var isEmpty: Bool {
        restored.isEmpty && reassigned.isEmpty && ignored.isEmpty
    }
}
