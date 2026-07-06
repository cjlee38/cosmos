import Foundation

enum WorkspaceError: Error, Equatable, CustomStringConvertible {
    case invalidWorkspaceName(String)
    case windowNotFound(WindowID)
    case windowNotInActiveWorkspace(WindowID, String)
    case noFocusedWindow
    case frameUnavailable(WindowID)

    var description: String {
        switch self {
        case let .invalidWorkspaceName(workspace):
            "Invalid workspace name: \(workspace)"
        case let .windowNotFound(id):
            "Window not found: \(id)"
        case let .windowNotInActiveWorkspace(id, workspace):
            "Window \(id) belongs to inactive workspace \(workspace)."
        case .noFocusedWindow:
            "No focused window."
        case let .frameUnavailable(id):
            "Window frame is unavailable: \(id)"
        }
    }
}

public enum RestoreResult: Equatable {
    case restored
    case alreadyVisible
}

public struct WorkspaceSwitchResult {
    public let workspace: String
    public let sync: WorkspaceSyncSummary

    public init(workspace: String, sync: WorkspaceSyncSummary) {
        self.workspace = workspace
        self.sync = sync
    }
}

public enum WindowFocusResult: Equatable {
    case focused(WindowID)
    case noWindowsInWorkspace(String)
}

public enum FocusedWindowWorkspaceSyncResult: Equatable {
    case noFocusedWindow
    case unmanagedWindow(WindowID)
    case alreadyActive(windowID: WindowID, workspace: String)
    case switched(windowID: WindowID, workspace: String)
}

public struct WindowMoveResult: Equatable {
    public let windowID: WindowID
    public let workspace: String

    public init(windowID: WindowID, workspace: String) {
        self.windowID = windowID
        self.workspace = workspace
    }
}

public struct WorkspaceSyncSummary {
    public static let empty = WorkspaceSyncSummary(autoAssigned: [], removed: [])

    public let autoAssigned: [(WindowID, String)]
    public let removed: [WindowID]

    public init(autoAssigned: [(WindowID, String)], removed: [WindowID]) {
        self.autoAssigned = autoAssigned
        self.removed = removed
    }

    public var isEmpty: Bool {
        autoAssigned.isEmpty && removed.isEmpty
    }
}

public struct WindowListResult {
    public let windows: [WindowSnapshot]
    public let sync: WorkspaceSyncSummary

    public init(windows: [WindowSnapshot], sync: WorkspaceSyncSummary) {
        self.windows = windows
        self.sync = sync
    }
}

public struct RestoreAllHiddenWindowsResult: Equatable {
    public let restored: [WindowID]
    public let skipped: [WindowID]

    public init(restored: [WindowID], skipped: [WindowID]) {
        self.restored = restored
        self.skipped = skipped
    }
}

public struct WindowBootstrapResult {
    public let hiddenRecords: HiddenWindowRecordStartupApplyResult

    public init(hiddenRecords: HiddenWindowRecordStartupApplyResult) {
        self.hiddenRecords = hiddenRecords
    }
}
