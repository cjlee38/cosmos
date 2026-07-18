import Foundation

public struct HiddenWindowRecordAssignment: Equatable {
    public let windowID: WindowID
    public let workspace: WorkspaceID

    public init(windowID: WindowID, workspace: WorkspaceID) {
        self.windowID = windowID
        self.workspace = workspace
    }
}

public struct HiddenWindowRecordStartupApplyResult: Equatable {
    public static let empty = HiddenWindowRecordStartupApplyResult(
        restored: [],
        reassigned: [],
        ignored: [],
        failed: []
    )

    public let restored: [WindowID]
    public let reassigned: [HiddenWindowRecordAssignment]
    public let ignored: [HiddenWindowRecord]
    public let failed: [WindowID]

    public init(
        restored: [WindowID],
        reassigned: [HiddenWindowRecordAssignment],
        ignored: [HiddenWindowRecord],
        failed: [WindowID]
    ) {
        self.restored = restored
        self.reassigned = reassigned
        self.ignored = ignored
        self.failed = failed
    }

    public var isEmpty: Bool {
        restored.isEmpty && reassigned.isEmpty && ignored.isEmpty && failed.isEmpty
    }
}
