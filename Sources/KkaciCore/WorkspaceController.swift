import Foundation

public enum WorkspaceError: Error, CustomStringConvertible {
    case invalidWorkspaceName(String)
    case windowNotFound(WindowID)
    case noFocusedWindow
    case frameUnavailable(WindowID)

    public var description: String {
        switch self {
        case .invalidWorkspaceName(let workspace):
            "Invalid workspace name: \(workspace)"
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

public enum FocusedWindowWorkspaceSyncResult: Equatable {
    case noFocusedWindow
    case unmanagedWindow(WindowID)
    case alreadyActive(windowID: WindowID, workspace: String)
    case switched(windowID: WindowID, workspace: String)
}

public struct WindowMoveResult: Equatable {
    public let windowID: WindowID
    public let workspace: String
    public let replacementFocus: WindowFocusResult?

    public init(windowID: WindowID, workspace: String, replacementFocus: WindowFocusResult?) {
        self.windowID = windowID
        self.workspace = workspace
        self.replacementFocus = replacementFocus
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

public final class WorkspaceController {
    private let windowSystem: any WindowSystem
    private let displayProvider: any HidePointProviding
    private let configStore: (any KkaciConfigStore)?

    private var state: WorkspaceState
    private var config: KkaciConfig
    private var isConfigPersistenceEnabled: Bool

    public var activeWorkspace: String {
        state.activeWorkspace
    }

    public var workspaces: [String] {
        state.workspaces
    }

    public init(
        windowSystem: any WindowSystem,
        displayProvider: any HidePointProviding,
        config: KkaciConfig = .default,
        configStore: (any KkaciConfigStore)? = nil,
        isConfigPersistenceEnabled: Bool = true
    ) {
        self.windowSystem = windowSystem
        self.displayProvider = displayProvider
        self.configStore = configStore
        self.config = config
        self.isConfigPersistenceEnabled = configStore != nil && isConfigPersistenceEnabled
        self.state = WorkspaceState(workspaces: config.workspaces)
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
        let workspace = try ensureWorkspace(workspace)
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }
        try assignWindow(id, to: workspace)
        return id
    }

    public func assignWindow(_ id: WindowID, to workspace: String) throws {
        _ = syncWindows()
        let workspace = try ensureWorkspace(workspace)
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        state.assign(id, to: workspace)

        if workspace == activeWorkspace {
            _ = try restoreWindowWithoutSync(id)
            windowSystem.focus(id)
        } else {
            try hideWindowWithoutSync(id)
        }
    }

    public func captureVisibleWindows(into workspace: String) throws -> WorkspaceSyncSummary {
        let result = syncWindows()
        let workspace = try ensureWorkspace(workspace)
        let visibleIDs = result.windows
            .filter { !$0.isMinimized }
            .map(\.id)
        state.capture(visibleIDs, into: workspace)
        return result.sync
    }

    public func switchWorkspace(to workspace: String) throws -> WorkspaceSyncSummary {
        let sync = syncWindows().sync
        try switchWorkspaceWithoutSync(to: workspace)
        return sync
    }

    public func syncWorkspaceToFocusedWindow() throws -> FocusedWindowWorkspaceSyncResult {
        _ = syncWindows()

        guard let id = windowSystem.focusedWindowID() else {
            return .noFocusedWindow
        }

        guard windowSystem.contains(id),
              let workspace = state.membership(for: id)
        else {
            return .unmanagedWindow(id)
        }

        guard workspace != activeWorkspace else {
            state.recordFocus(id, in: workspace)
            return .alreadyActive(windowID: id, workspace: workspace)
        }

        state.recordFocus(id, in: workspace)
        try switchWorkspaceWithoutSync(to: workspace)
        return .switched(windowID: id, workspace: workspace)
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

    public func moveFocusedWindow(to workspace: String) throws -> WindowMoveResult {
        _ = syncWindows()
        let workspace = try ensureWorkspace(workspace)
        guard let id = windowSystem.focusedWindowID() else {
            throw WorkspaceError.noFocusedWindow
        }
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let sourceWorkspace = state.membership(for: id) ?? activeWorkspace
        state.assign(id, to: workspace)

        if workspace == activeWorkspace {
            _ = try restoreWindowWithoutSync(id)
            windowSystem.focus(id)
            return WindowMoveResult(windowID: id, workspace: workspace, replacementFocus: nil)
        }

        try hideWindowWithoutSync(id)
        let replacementFocus = focusReplacementAfterMovingWindow(id, from: sourceWorkspace)
        return WindowMoveResult(windowID: id, workspace: workspace, replacementFocus: replacementFocus)
    }

    @discardableResult
    public func createWorkspace(named workspace: String) throws -> String {
        try ensureWorkspace(workspace)
    }

    public func applyConfig(_ config: KkaciConfig, enablePersistence: Bool = true) {
        self.isConfigPersistenceEnabled = configStore != nil && enablePersistence
        state.applyWorkspaces(config.workspaces)
        self.config = KkaciConfig(
            workspaces: WorkspaceConfig(names: state.workspaces),
            bindings: config.bindings
        )
    }

    public func hideWindow(_ id: WindowID) throws {
        _ = syncWindows()
        try hideWindowWithoutSync(id)
    }

    public func restoreWindow(_ id: WindowID, focus: Bool = false) throws -> RestoreResult {
        _ = syncWindows()
        let result = try restoreWindowWithoutSync(id)
        if focus {
            windowSystem.focus(id)
        }
        return result
    }

    private func hideWindowWithoutSync(_ id: WindowID) throws {
        guard windowSystem.contains(id) else {
            throw WorkspaceError.windowNotFound(id)
        }

        let frame = try currentOrStoredFrame(for: id)
        state.storeHiddenFrameIfNeeded(frame, for: id)

        let point = displayProvider.hidePoint(for: frame)
        try windowSystem.setPosition(point, for: id)
    }

    private func restoreWindowWithoutSync(_ id: WindowID) throws -> RestoreResult {
        guard windowSystem.contains(id) else {
            state.clearHiddenFrame(for: id)
            throw WorkspaceError.windowNotFound(id)
        }

        guard let frame = state.hiddenFrame(for: id) else {
            return .alreadyVisible
        }

        try windowSystem.setFrame(frame, for: id)
        state.clearHiddenFrame(for: id)
        return .restored
    }

    private func syncWindows() -> WindowListResult {
        let windows = windowSystem.refresh()
        let aliveIDs = Set(windows.map(\.id))
        return WindowListResult(windows: windows, sync: state.sync(aliveWindowIDs: aliveIDs))
    }

    private func ensureWorkspace(_ workspace: String) throws -> String {
        let workspace = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workspace.isEmpty else {
            throw WorkspaceError.invalidWorkspaceName(workspace)
        }

        if state.containsWorkspace(workspace) {
            return workspace
        }

        let config = config.addingWorkspace(named: workspace)
        if isConfigPersistenceEnabled {
            try configStore?.save(config)
        }
        self.config = config
        state.addWorkspace(workspace)
        return workspace
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

    private func switchWorkspaceWithoutSync(to workspace: String) throws {
        let workspace = try ensureWorkspace(workspace)
        let oldFocusedWindow = focusedWindowInActiveWorkspace()
            ?? state.focusTarget(for: activeWorkspace, fallback: nil)
        state.activate(workspace)

        var firstRestored: WindowID?
        for id in state.windowIDs(in: workspace) {
            _ = try restoreWindowWithoutSync(id)
            firstRestored = firstRestored ?? id
        }

        let focusTarget = state.focusTarget(for: workspace, fallback: firstRestored)
        if let focusTarget {
            windowSystem.focus(focusTarget)
            state.recordFocus(focusTarget, in: workspace)
        }

        for id in hideOrder(targetWorkspace: workspace, oldFocusedWindow: oldFocusedWindow) {
            try hideWindowWithoutSync(id)
        }
    }

    private func focusedWindowInActiveWorkspace() -> WindowID? {
        guard let id = windowSystem.focusedWindowID(),
              state.membership(for: id) == activeWorkspace
        else {
            return nil
        }
        return id
    }

    private func focusReplacementAfterMovingWindow(_ movedID: WindowID, from sourceWorkspace: String) -> WindowFocusResult? {
        guard sourceWorkspace == activeWorkspace else {
            return nil
        }

        guard let target = state.nextWindow(in: activeWorkspace, after: movedID) else {
            state.clearFocus(movedID, in: activeWorkspace)
            return .noWindowsInWorkspace(activeWorkspace)
        }

        windowSystem.focus(target)
        state.recordFocus(target, in: activeWorkspace)
        return .focused(target)
    }

    private func hideOrder(targetWorkspace: String, oldFocusedWindow: WindowID?) -> [WindowID] {
        var ids = state.assignedWindowIDs
            .filter { state.membership(for: $0) != targetWorkspace }
            .sorted()

        if let oldFocusedWindow, let index = ids.firstIndex(of: oldFocusedWindow) {
            ids.remove(at: index)
            ids.append(oldFocusedWindow)
        }

        return ids
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
