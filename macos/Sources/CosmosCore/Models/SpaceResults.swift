import Foundation

enum SpaceError: Error, Equatable, CustomStringConvertible {
    case displayNotFound(DisplayID)
    case windowNotFound(WindowID)
    case windowNotInCurrentSpace(WindowID, String)
    case windowNotInVisibleSpace(WindowID, String)
    case noFocusedWindow
    case noDisplayAvailable
    case frameUnavailable(WindowID)

    var description: String {
        switch self {
        case let .displayNotFound(displayID):
            "Display not found: \(displayID)"
        case let .windowNotFound(id):
            "Window not found: \(id)"
        case let .windowNotInCurrentSpace(id, space):
            "Window \(id) belongs to space \(space), which is not current."
        case let .windowNotInVisibleSpace(id, space):
            "Window \(id) belongs to space \(space), which is not visible."
        case .noFocusedWindow:
            "No focused window."
        case .noDisplayAvailable:
            "No display is available."
        case let .frameUnavailable(id):
            "Window frame is unavailable: \(id)"
        }
    }
}

struct SpaceTransactionError: Error, CustomStringConvertible {
    let applyError: Error
    let rollbackError: Error

    var description: String {
        "Space operation failed: \(applyError); rollback failed: \(rollbackError)"
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

public enum FocusedWindowSpaceSyncResult: Equatable {
    case noFocusedWindow
    case unmanagedWindow(WindowID)
    case alreadyActive(windowID: WindowID, space: String)
    case switched(windowID: WindowID, space: String)
}

public enum WindowMoveOutcome: Equatable {
    case moved
    case alreadyInSpace
}

public struct WindowMoveResult: Equatable {
    public let windowID: WindowID
    public let previousSpace: String
    public let space: String
    public let outcome: WindowMoveOutcome

    public init(
        windowID: WindowID,
        previousSpace: String,
        space: String,
        outcome: WindowMoveOutcome
    ) {
        self.windowID = windowID
        self.previousSpace = previousSpace
        self.space = space
        self.outcome = outcome
    }
}

public struct SpaceMembershipChange: Equatable {
    public let windowID: WindowID
    public let previousSpace: String?
    public let space: String?

    public init(windowID: WindowID, previousSpace: String?, space: String?) {
        self.windowID = windowID
        self.previousSpace = previousSpace
        self.space = space
    }
}

public struct SpaceSyncSummary {
    public let membershipChanges: [SpaceMembershipChange]

    public init(membershipChanges: [SpaceMembershipChange]) {
        self.membershipChanges = membershipChanges
    }

    public var autoAssigned: [(WindowID, String)] {
        membershipChanges.compactMap { change in
            guard change.previousSpace == nil, let space = change.space else {
                return nil
            }
            return (change.windowID, space)
        }
    }

    public var removed: [WindowID] {
        membershipChanges.compactMap { change in
            change.space == nil ? change.windowID : nil
        }
    }

    public var affectedWindowIDs: Set<WindowID> {
        Set(membershipChanges.map(\.windowID))
    }

    public var affectedSpaces: Set<String> {
        Set(membershipChanges.flatMap { change in
            [change.previousSpace, change.space].compactMap { $0 }
        })
    }

    public var isEmpty: Bool {
        membershipChanges.isEmpty
    }
}

public struct ExternalWindowEventResult {
    public let sync: SpaceSyncSummary
    public let focusedWindowSync: FocusedWindowSpaceSyncResult?
    public let continuityRecovery: WindowContinuityRecoveryStatus

    public init(
        sync: SpaceSyncSummary,
        focusedWindowSync: FocusedWindowSpaceSyncResult?,
        continuityRecovery: WindowContinuityRecoveryStatus = .complete
    ) {
        self.sync = sync
        self.focusedWindowSync = focusedWindowSync
        self.continuityRecovery = continuityRecovery
    }
}

public struct WindowContinuityRecoveryStatus {
    public let pendingWindowIDs: Set<WindowID>
    public let failedWindowIDs: Set<WindowID>
    public let attempts: [ContinuityRecoveryAttempt]

    public init(
        pendingWindowIDs: Set<WindowID>,
        failedWindowIDs: Set<WindowID>,
        attempts: [ContinuityRecoveryAttempt] = []
    ) {
        self.pendingWindowIDs = pendingWindowIDs
        self.failedWindowIDs = failedWindowIDs
        self.attempts = attempts
    }

    public static let complete = WindowContinuityRecoveryStatus(
        pendingWindowIDs: [],
        failedWindowIDs: [],
        attempts: []
    )

    public var isPending: Bool {
        !pendingWindowIDs.isEmpty
    }
}

public struct ContinuityRecoveryAttempt {
    public let windowID: WindowID
    public let space: SpaceID?
    public let operation: String
    public let targetFrame: WindowFrame?
    public let resultingFrame: WindowFrame?
    public let outcome: String

    public init(
        windowID: WindowID,
        space: SpaceID?,
        operation: String,
        targetFrame: WindowFrame?,
        resultingFrame: WindowFrame?,
        outcome: String
    ) {
        self.windowID = windowID
        self.space = space
        self.operation = operation
        self.targetFrame = targetFrame
        self.resultingFrame = resultingFrame
        self.outcome = outcome
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
    public let terminatedApplicationPIDs: Set<pid_t>
    public let destroyedWindowIDs: Set<WindowID>
    public let userMovedWindowIDs: Set<WindowID>

    public init(
        displayConfigurationChanged: Bool = false,
        focusPolicy: ExternalWindowFocusPolicy = .never,
        terminatedApplicationPIDs: Set<pid_t> = [],
        destroyedWindowIDs: Set<WindowID> = [],
        userMovedWindowIDs: Set<WindowID> = []
    ) {
        self.displayConfigurationChanged = displayConfigurationChanged
        self.focusPolicy = focusPolicy
        self.terminatedApplicationPIDs = terminatedApplicationPIDs
        self.destroyedWindowIDs = destroyedWindowIDs
        self.userMovedWindowIDs = userMovedWindowIDs
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
