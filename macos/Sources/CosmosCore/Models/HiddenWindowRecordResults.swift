import Foundation

public struct HiddenWindowRecordAssignment: Equatable {
    public let windowID: WindowID
    public let space: SpaceID

    public init(windowID: WindowID, space: SpaceID) {
        self.windowID = windowID
        self.space = space
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
