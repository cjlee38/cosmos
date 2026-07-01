import CoreGraphics
import Foundation

public struct SnapshotWorkspaceAssignment: Equatable {
    public let windowID: WindowID
    public let workspace: String

    public init(windowID: WindowID, workspace: String) {
        self.windowID = windowID
        self.workspace = workspace
    }
}

public struct SnapshotStartupApplyResult: Equatable {
    public static let empty = SnapshotStartupApplyResult(restored: [], reassigned: [], ignored: [])

    public let restored: [WindowID]
    public let reassigned: [SnapshotWorkspaceAssignment]
    public let ignored: [HiddenWindowSnapshot]

    public init(restored: [WindowID], reassigned: [SnapshotWorkspaceAssignment], ignored: [HiddenWindowSnapshot]) {
        self.restored = restored
        self.reassigned = reassigned
        self.ignored = ignored
    }

    public var isEmpty: Bool {
        restored.isEmpty && reassigned.isEmpty && ignored.isEmpty
    }
}

enum HiddenWindowSnapshotStartupAction: Equatable {
    case restoreAndAssign(workspace: String)
    case assignOnly(workspace: String)
    case ignore

    var workspace: String? {
        switch self {
        case .restoreAndAssign(let workspace), .assignOnly(let workspace):
            workspace
        case .ignore:
            nil
        }
    }

    var shouldRestore: Bool {
        switch self {
        case .restoreAndAssign:
            true
        case .assignOnly, .ignore:
            false
        }
    }
}

enum HiddenWindowSnapshotPolicy {
    static func makeSnapshot(
        window: WindowSnapshot,
        workspace: String,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint
    ) -> HiddenWindowSnapshot {
        HiddenWindowSnapshot(
            windowID: window.id,
            pid: window.app.pid,
            bundleID: window.app.bundleID,
            appName: window.app.name,
            title: window.title,
            workspace: workspace,
            originalFrame: originalFrame,
            hiddenPosition: hiddenPosition
        )
    }

    static func startupAction(
        for snapshot: HiddenWindowSnapshot,
        liveWindow: WindowSnapshot?
    ) -> HiddenWindowSnapshotStartupAction {
        guard let liveWindow,
              liveWindow.app.pid == snapshot.pid,
              let currentFrame = liveWindow.frame
        else {
            return .ignore
        }

        if isPoint(currentFrame.origin, near: snapshot.hiddenPosition) {
            return .restoreAndAssign(workspace: snapshot.workspace)
        }

        if isFrame(currentFrame, near: snapshot.originalFrame) {
            return .assignOnly(workspace: snapshot.workspace)
        }

        return .ignore
    }

    private static func isFrame(_ lhs: WindowFrame, near rhs: WindowFrame) -> Bool {
        isPoint(lhs.origin, near: rhs.origin) && isSize(lhs.size, near: rhs.size)
    }

    private static func isPoint(_ lhs: CGPoint, near rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 2 && abs(lhs.y - rhs.y) <= 2
    }

    private static func isSize(_ lhs: CGSize, near rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }
}
