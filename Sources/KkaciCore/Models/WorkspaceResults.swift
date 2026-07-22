import Foundation

enum WorkspaceError: Error, Equatable, CustomStringConvertible {
    case displayNotFound(DisplayID)
    case windowNotFound(WindowID)
    case windowNotInCurrentWorkspace(WindowID, String)
    case windowNotInVisibleWorkspace(WindowID, String)
    case noFocusedWindow
    case noDisplayAvailable
    case frameUnavailable(WindowID)

    var description: String {
        switch self {
        case let .displayNotFound(displayID):
            "Display not found: \(displayID)"
        case let .windowNotFound(id):
            "Window not found: \(id)"
        case let .windowNotInCurrentWorkspace(id, workspace):
            "Window \(id) belongs to workspace \(workspace), which is not current."
        case let .windowNotInVisibleWorkspace(id, workspace):
            "Window \(id) belongs to workspace \(workspace), which is not visible."
        case .noFocusedWindow:
            "No focused window."
        case .noDisplayAvailable:
            "No display is available."
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

enum RestoreResult: Equatable {
    case restored
    case alreadyVisible
}

public enum FocusedWindowWorkspaceSyncResult: Equatable {
    case noFocusedWindow
    case unmanagedWindow(WindowID)
    case alreadyActive(windowID: WindowID, workspace: String)
    case switched(windowID: WindowID, workspace: String)
}

public enum WindowMoveOutcome: Equatable {
    case moved
    case alreadyInWorkspace
}

public struct WindowMoveResult: Equatable {
    public let windowID: WindowID
    public let previousWorkspace: String
    public let workspace: String
    public let outcome: WindowMoveOutcome

    public init(
        windowID: WindowID,
        previousWorkspace: String,
        workspace: String,
        outcome: WindowMoveOutcome
    ) {
        self.windowID = windowID
        self.previousWorkspace = previousWorkspace
        self.workspace = workspace
        self.outcome = outcome
    }
}

public struct WorkspaceMembershipChange: Equatable {
    public let windowID: WindowID
    public let previousWorkspace: String?
    public let workspace: String?

    public init(windowID: WindowID, previousWorkspace: String?, workspace: String?) {
        self.windowID = windowID
        self.previousWorkspace = previousWorkspace
        self.workspace = workspace
    }
}

public struct WorkspaceSyncSummary {
    public let membershipChanges: [WorkspaceMembershipChange]

    public init(membershipChanges: [WorkspaceMembershipChange]) {
        self.membershipChanges = membershipChanges
    }

    public var autoAssigned: [(WindowID, String)] {
        membershipChanges.compactMap { change in
            guard change.previousWorkspace == nil, let workspace = change.workspace else {
                return nil
            }
            return (change.windowID, workspace)
        }
    }

    public var removed: [WindowID] {
        membershipChanges.compactMap { change in
            change.workspace == nil ? change.windowID : nil
        }
    }

    public var affectedWindowIDs: Set<WindowID> {
        Set(membershipChanges.map(\.windowID))
    }

    public var affectedWorkspaces: Set<String> {
        Set(membershipChanges.flatMap { change in
            [change.previousWorkspace, change.workspace].compactMap { $0 }
        })
    }

    public var isEmpty: Bool {
        membershipChanges.isEmpty
    }
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

public enum ExternalWindowFocusPolicy {
    case never
    case always
    case visibleFocusedWindow
}

public struct ExternalWindowChange {
    public let displayConfigurationChanged: Bool
    public let focusPolicy: ExternalWindowFocusPolicy

    public init(
        displayConfigurationChanged: Bool = false,
        focusPolicy: ExternalWindowFocusPolicy = .never
    ) {
        self.displayConfigurationChanged = displayConfigurationChanged
        self.focusPolicy = focusPolicy
    }
}

public struct RestoreAllHiddenWindowsResult: Equatable {
    public let restored: [WindowID]
    public let unavailable: [WindowID]
    public let failed: [WindowID]

    public init(restored: [WindowID], unavailable: [WindowID], failed: [WindowID]) {
        self.restored = restored
        self.unavailable = unavailable
        self.failed = failed
    }
}
