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

struct WorkspaceTransactionError: Error, CustomStringConvertible {
    let applyError: Error
    let rollbackError: Error

    var description: String {
        "Workspace operation failed: \(applyError); rollback failed: \(rollbackError)"
    }
}

struct ShutdownRestoreError: Error, CustomStringConvertible {
    let failedWindowIDs: [WindowID]
    let recordFlushError: Error?

    var description: String {
        let windows = failedWindowIDs.map(String.init).joined(separator: ", ")
        guard let recordFlushError else {
            return "Failed to restore windows during shutdown: \(windows)"
        }
        return "Failed to restore windows during shutdown: \(windows); record flush failed: \(recordFlushError)"
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

struct WindowDiscoveryResult {
    let windows: [WindowSnapshot]
    let sync: WorkspaceSyncSummary
}

public struct ExternalWindowEventResult {
    public let sync: WorkspaceSyncSummary
    public let focusedWindowSync: FocusedWindowWorkspaceSyncResult?

    public init(
        sync: WorkspaceSyncSummary,
        focusedWindowSync: FocusedWindowWorkspaceSyncResult?
    ) {
        self.sync = sync
        self.focusedWindowSync = focusedWindowSync
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
