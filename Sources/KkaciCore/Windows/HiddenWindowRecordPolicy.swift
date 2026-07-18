import CoreGraphics
import Foundation

enum HiddenWindowRecordStartupAction: Equatable {
    case restoreAndAssign(workspace: WorkspaceID)
    case assignOnly(workspace: WorkspaceID)
    case ignore

    var workspace: WorkspaceID? {
        switch self {
        case let .restoreAndAssign(workspace), let .assignOnly(workspace):
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

enum HiddenWindowRecordPolicy {
    static func makeRecord(
        window: WindowSnapshot,
        workspace: WorkspaceID,
        originalFrame: WindowFrame,
        hiddenPosition: CGPoint
    ) -> HiddenWindowRecord {
        HiddenWindowRecord(
            windowID: window.id,
            pid: window.app.pid,
            workspace: workspace,
            originalFrame: originalFrame,
            hiddenPosition: hiddenPosition
        )
    }

    static func startupAction(
        for record: HiddenWindowRecord,
        liveWindow: WindowSnapshot?
    ) -> HiddenWindowRecordStartupAction {
        guard let liveWindow,
              liveWindow.app.pid == record.pid,
              let currentFrame = liveWindow.frame
        else {
            return .ignore
        }

        if isPoint(currentFrame.origin, near: record.hiddenPosition) {
            return .restoreAndAssign(workspace: record.workspace)
        }

        if isFrame(currentFrame, near: record.originalFrame) {
            return .assignOnly(workspace: record.workspace)
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
