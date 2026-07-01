import Foundation

public enum WorkspaceError: Error, CustomStringConvertible {
    case invalidWorkspace(String, allowed: [String])
    case windowNotFound(WindowID)
    case noFocusedWindow
    case frameUnavailable(WindowID)

    public var description: String {
        switch self {
        case .invalidWorkspace(let workspace, let allowed):
            "Invalid workspace: \(workspace). Allowed workspaces: \(allowed.joined(separator: ", "))"
        case .windowNotFound(let id):
            "Window not found: \(id)"
        case .noFocusedWindow:
            "No focused window."
        case .frameUnavailable(let id):
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

public final class WorkspaceController {
    private let windowSystem: any WindowSystem
    private let displayProvider: any HidePointProviding

    private var state = WorkspaceState()

    public var activeWorkspace: String {
        state.activeWorkspace
    }

    public var workspaces: [String] {
        state.workspaces
    }

    public init(windowSystem: any WindowSystem, displayProvider: any HidePointProviding) {
        self.windowSystem = windowSystem
        self.displayProvider = displayProvider
    }

    public func listWindows() -> WindowListResult {
        syncWindows()
    }

    public func membership(for id: WindowID) -> String? {
        state.membership(for: id)
    }

    public func isHiddenByWorkspace(_ id: WindowID) -> Bool {
        state.isHidden(id)
    }

    public func focusedWindowID() -> WindowID? {
        _ = syncWindows()
        return windowSystem.focusedWindowID()
    }

    public func assignFocused(to workspace: String) throws -> WindowID {
        _ = syncWindows()
        try validateWorkspace(workspace)
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }
        try assignWindow(id, to: workspace)
        return id
    }

    public func assignWindow(_ id: WindowID, to workspace: String) throws {
        _ = syncWindows()
        try validateWorkspace(workspace)
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        state.assign(id, to: workspace)

        if workspace == activeWorkspace {
            _ = try restoreWindow(id)
            windowSystem.focus(id)
        } else {
            try hideWindow(id)
        }
    }

    public func captureVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        try validateWorkspace(workspace)
        let visibleIDs = result.windows
            .filter { !$0.isMinimized }
            .map(\.id)
        state.capture(visibleIDs, into: workspace)
        return result.sync
    }

    public func switchWorkspace(to workspace: String) throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try validateWorkspace(workspace)
        state.activate(workspace)

        var firstRestored: WindowID?
        for id in state.assignedWindowIDs.sorted() {
            if state.membership(for: id) == workspace {
                _ = try restoreWindow(id)
                firstRestored = firstRestored ?? id
            } else {
                try hideWindow(id)
            }
        }

        let focusTarget = state.focusTarget(for: workspace, fallback: firstRestored)
        if let focusTarget {
            windowSystem.focus(focusTarget)
            state.recordFocus(focusTarget, in: workspace)
        }
        return sync
    }

    public func switchToNextWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.nextWorkspace(after: activeWorkspace)
        let sync = try switchWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    public func switchToPreviousWorkspace() throws -> WorkspaceSwitchResult {
        let workspace = state.previousWorkspace(before: activeWorkspace)
        let sync = try switchWorkspace(to: workspace)
        return WorkspaceSwitchResult(workspace: workspace, sync: sync)
    }

    public func focusNextWindow() -> WindowFocusResult {
        focusCycledWindow(next: true)
    }

    public func focusPreviousWindow() -> WindowFocusResult {
        focusCycledWindow(next: false)
    }

    public func hideWindow(_ id: WindowID) throws {
        _ = syncWindows()
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let frame = try currentOrStoredFrame(for: id)
        state.storeHiddenFrameIfNeeded(frame, for: id)

        let point = displayProvider.hidePoint(for: frame)
        try windowSystem.setPosition(point, for: id)
    }

    public func restoreWindow(_ id: WindowID, focus: Bool = false) throws -> RestoreResult {
        _ = syncWindows()
        guard windowSystem.contains(id) else {
            state.clearHiddenFrame(for: id)
            throw WorkspaceError.windowNotFound(id)
        }

        guard let frame = state.hiddenFrame(for: id) else {
            if focus {
                windowSystem.focus(id)
            }
            return .alreadyVisible
        }

        try windowSystem.setFrame(frame, for: id)
        state.clearHiddenFrame(for: id)
        if focus {
            windowSystem.focus(id)
        }
        return .restored
    }

    private func syncWindows() -> WindowListResult {
        let windows = windowSystem.refresh()
        let aliveIDs = Set(windows.map(\.id))
        return WindowListResult(windows: windows, sync: state.sync(aliveWindowIDs: aliveIDs))
    }

    private func validateWorkspace(_ workspace: String) throws {
        guard state.containsWorkspace(workspace) else {
            throw WorkspaceError.invalidWorkspace(workspace, allowed: state.workspaces)
        }
    }

    private func focusCycledWindow(next: Bool) -> WindowFocusResult {
        _ = syncWindows()

        let current = focusedWindowInActiveWorkspace()
            ?? state.focusTarget(for: activeWorkspace, fallback: nil)
        let target = next
            ? state.nextWindow(in: activeWorkspace, after: current)
            : state.previousWindow(in: activeWorkspace, before: current)

        guard let target else {
            return .noWindowsInWorkspace(activeWorkspace)
        }

        windowSystem.focus(target)
        state.recordFocus(target, in: activeWorkspace)
        return .focused(target)
    }

    private func focusedWindowInActiveWorkspace() -> WindowID? {
        guard let id = windowSystem.focusedWindowID(),
              state.membership(for: id) == activeWorkspace
        else {
            return nil
        }
        return id
    }

    private func currentOrStoredFrame(for id: WindowID) throws -> WindowFrame {
        if let hiddenFrame = state.hiddenFrame(for: id) {
            return hiddenFrame
        }
        guard let frame = windowSystem.frame(for: id) else {
            throw WorkspaceError.frameUnavailable(id)
        }
        return frame
    }
}
