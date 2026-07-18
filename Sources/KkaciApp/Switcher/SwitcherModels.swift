import AppKit
import KkaciCore

struct WindowSwitcherItem {
    let windowID: WindowID
    let appName: String
    let title: String
    let frame: WindowFrame?
    let preview: NSImage?
    let icon: NSImage?

    var displayTitle: String {
        title.isEmpty ? "(untitled)" : title
    }
}

struct WorkspaceSwitcherGroup {
    let id: String
    let windows: [WindowSwitcherItem]
    let preview: NSImage?
    let shortcutKey: String?

    init(
        id: String,
        windows: [WindowSwitcherItem],
        preview: NSImage?,
        shortcutKey: String? = nil
    ) {
        self.id = id
        self.windows = windows
        self.preview = preview
        self.shortcutKey = shortcutKey
    }
}

enum ActiveSwitcherSession {
    case windows(selection: SwitcherSession<WindowID>, anchorFrame: WindowFrame?)
    case workspaces(selection: SwitcherSession<String>, anchorFrame: WindowFrame?)

    var windowSelection: SwitcherSession<WindowID>? {
        guard case let .windows(selection, _) = self else {
            return nil
        }
        return selection
    }

    var workspaceSelection: SwitcherSession<String>? {
        guard case let .workspaces(selection, _) = self else {
            return nil
        }
        return selection
    }

    var description: String {
        switch self {
        case let .windows(selection, _):
            "windows selected=\(selection.selectedIndex)"
        case let .workspaces(selection, _):
            "workspaces selected=\(selection.selectedIndex)"
        }
    }

    mutating func stepWindow(_ direction: SwitcherDirection, wraps: Bool) -> Bool {
        guard case let .windows(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        selection.step(direction, wraps: wraps)
        self = .windows(selection: selection, anchorFrame: anchorFrame)
        return true
    }

    mutating func stepWorkspace(_ direction: SwitcherDirection) -> Bool {
        guard case let .workspaces(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        selection.step(direction)
        self = .workspaces(selection: selection, anchorFrame: anchorFrame)
        return true
    }

    mutating func moveWindow(_ direction: SwitcherArrowDirection) -> Bool {
        guard case let .windows(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        selection.move(direction)
        self = .windows(selection: selection, anchorFrame: anchorFrame)
        return true
    }

    mutating func selectWindow(_ windowID: WindowID) -> Bool {
        guard case let .windows(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        guard selection.select(windowID) else {
            return false
        }
        self = .windows(selection: selection, anchorFrame: anchorFrame)
        return true
    }

    mutating func selectWorkspace(_ workspace: String) -> Bool {
        guard case let .workspaces(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        guard selection.select(workspace) else {
            return false
        }
        self = .workspaces(selection: selection, anchorFrame: anchorFrame)
        return true
    }

    mutating func reconcileWindows(_ windowIDs: [WindowID], anchorFrame: WindowFrame?) -> Bool {
        guard case let .windows(currentSelection, _) = self else {
            return false
        }
        var selection = currentSelection
        guard selection.reconcile(with: windowIDs) else {
            return false
        }
        self = .windows(selection: selection, anchorFrame: anchorFrame)
        return true
    }

    mutating func reconcileWorkspaces(_ workspaces: [String], anchorFrame: WindowFrame?) -> Bool {
        guard case let .workspaces(currentSelection, _) = self else {
            return false
        }
        var selection = currentSelection
        guard selection.reconcile(with: workspaces) else {
            return false
        }
        self = .workspaces(selection: selection, anchorFrame: anchorFrame)
        return true
    }
}
