import Foundation

struct WorkspaceState {
    private(set) var activeWorkspace: String
    private var didLoadInitialWindowSet = false
    private var knownWindowIDs: Set<WindowID> = []
    private var workspaceOrder: [String]
    private var memberships: [WindowID: String] = [:]
    private var hiddenFrames: [WindowID: WindowFrame] = [:]
    private var lastFocusedByWorkspace: [String: WindowID] = [:]

    init(workspaces: WorkspaceConfig = WorkspaceConfig(names: ["1", "2", "3"])) {
        self.workspaceOrder = workspaces.names
        self.activeWorkspace = workspaces.names[0]
    }

    var assignedWindowIDs: [WindowID] {
        Array(memberships.keys)
    }

    var workspaces: [String] {
        workspaceOrder
    }

    mutating func sync(aliveWindowIDs: Set<WindowID>) -> WorkspaceSyncSummary {
        if !didLoadInitialWindowSet {
            didLoadInitialWindowSet = true
            knownWindowIDs = aliveWindowIDs
            return .empty
        }

        let newIDs = aliveWindowIDs.subtracting(knownWindowIDs).sorted()
        let removedIDs = knownWindowIDs.subtracting(aliveWindowIDs).sorted()

        for id in newIDs {
            memberships[id] = activeWorkspace
        }

        for id in removedIDs {
            removeWindow(id)
        }

        knownWindowIDs = aliveWindowIDs

        return WorkspaceSyncSummary(
            autoAssigned: newIDs.map { ($0, activeWorkspace) },
            removed: removedIDs
        )
    }

    func membership(for id: WindowID) -> String? {
        memberships[id]
    }

    func isHidden(_ id: WindowID) -> Bool {
        hiddenFrames[id] != nil
    }

    func hiddenFrame(for id: WindowID) -> WindowFrame? {
        hiddenFrames[id]
    }

    var hiddenWindowIDs: [WindowID] {
        hiddenFrames.keys.sorted()
    }

    func containsWorkspace(_ workspace: String) -> Bool {
        workspaceOrder.contains(workspace)
    }

    mutating func addWorkspace(_ workspace: String) {
        if !workspaceOrder.contains(workspace) {
            workspaceOrder.append(workspace)
        }
    }

    mutating func applyWorkspaces(_ workspaces: WorkspaceConfig) {
        var nextOrder = workspaces.names
        let referencedWorkspaces = Set(
            Array(memberships.values) +
                Array(lastFocusedByWorkspace.keys) +
                [activeWorkspace]
        )

        for workspace in workspaceOrder where referencedWorkspaces.contains(workspace) {
            if !nextOrder.contains(workspace) {
                nextOrder.append(workspace)
            }
        }

        workspaceOrder = nextOrder
        if !workspaceOrder.contains(activeWorkspace) {
            activeWorkspace = workspaceOrder[0]
        }
    }

    mutating func activate(_ workspace: String) {
        activeWorkspace = workspace
    }

    mutating func assign(_ id: WindowID, to workspace: String) {
        memberships[id] = workspace
        lastFocusedByWorkspace[workspace] = id
    }

    mutating func capture(_ ids: [WindowID], into workspace: String) {
        for id in ids {
            memberships[id] = workspace
            knownWindowIDs.insert(id)
        }
    }

    mutating func storeHiddenFrameIfNeeded(_ frame: WindowFrame, for id: WindowID) {
        if hiddenFrames[id] == nil {
            hiddenFrames[id] = frame
        }
    }

    mutating func clearHiddenFrame(for id: WindowID) {
        hiddenFrames[id] = nil
    }

    mutating func recordFocus(_ id: WindowID, in workspace: String) {
        lastFocusedByWorkspace[workspace] = id
    }

    mutating func clearFocus(_ id: WindowID, in workspace: String) {
        if lastFocusedByWorkspace[workspace] == id {
            lastFocusedByWorkspace[workspace] = nil
        }
    }

    func focusTarget(for workspace: String, fallback: WindowID?) -> WindowID? {
        lastFocusedByWorkspace[workspace] ?? fallback
    }

    func nextWorkspace(after workspace: String) -> String {
        cycledValue(in: workspaceOrder, after: workspace, direction: .forward) ?? activeWorkspace
    }

    func previousWorkspace(before workspace: String) -> String {
        cycledValue(in: workspaceOrder, after: workspace, direction: .backward) ?? activeWorkspace
    }

    func windowIDs(in workspace: String) -> [WindowID] {
        memberships
            .filter { $0.value == workspace }
            .map(\.key)
            .sorted()
    }

    func nextWindow(in workspace: String, after id: WindowID?) -> WindowID? {
        cycledValue(in: windowIDs(in: workspace), after: id, direction: .forward)
    }

    func previousWindow(in workspace: String, before id: WindowID?) -> WindowID? {
        cycledValue(in: windowIDs(in: workspace), after: id, direction: .backward)
    }

    private mutating func removeWindow(_ id: WindowID) {
        memberships[id] = nil
        hiddenFrames[id] = nil
        for (workspace, windowID) in lastFocusedByWorkspace where windowID == id {
            lastFocusedByWorkspace[workspace] = nil
        }
    }

    private func cycledValue<T: Equatable>(in values: [T], after current: T?, direction: CycleDirection) -> T? {
        guard !values.isEmpty else {
            return nil
        }

        guard let current, let index = values.firstIndex(of: current) else {
            return values.first
        }

        switch direction {
        case .forward:
            return values[(index + 1) % values.count]
        case .backward:
            return values[(index + values.count - 1) % values.count]
        }
    }
}

private enum CycleDirection {
    case forward
    case backward
}
