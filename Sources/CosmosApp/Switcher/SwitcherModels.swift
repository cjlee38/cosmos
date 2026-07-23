import AppKit
import CosmosCore

struct SpaceShortcutBindings {
    private struct Entry {
        let spaceID: String
        let key: String
    }

    private let entries: [Entry]

    init(_ shortcuts: [ConfiguredShortcut]) {
        entries = shortcuts.compactMap { shortcut in
            guard case let .switchSpace(space) = shortcut.target,
                  let parsed = try? shortcut.parsed()
            else {
                return nil
            }
            return Entry(spaceID: space.rawValue, key: parsed.key)
        }
    }

    func key(for spaceID: String) -> String? {
        entries.first { $0.spaceID == spaceID }?.key
    }

    func spaceID(for key: String) -> String? {
        let key = key.lowercased()
        return entries.first { $0.key == key }?.spaceID
    }
}

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

enum SpacePreviewStyle {
    case spatial
    case applicationIcons
}

struct SpaceSwitcherGroup {
    let id: String
    let displayFrame: CGRect
    let windows: [WindowSwitcherItem]
    let preview: NSImage?
    let previewStyle: SpacePreviewStyle
    let shortcutKey: String?

    init(
        id: String,
        displayFrame: CGRect,
        windows: [WindowSwitcherItem],
        preview: NSImage?,
        previewStyle: SpacePreviewStyle = .spatial,
        shortcutKey: String? = nil
    ) {
        self.id = id
        self.displayFrame = displayFrame
        self.windows = windows
        self.preview = preview
        self.previewStyle = previewStyle
        self.shortcutKey = shortcutKey
    }
}

enum ActiveSwitcherSession {
    case windows(selection: SwitcherSession<WindowID>, anchorFrame: WindowFrame?)
    case spaces(selection: SwitcherSession<String>, anchorFrame: WindowFrame?)

    var windowSelection: SwitcherSession<WindowID>? {
        guard case let .windows(selection, _) = self else {
            return nil
        }
        return selection
    }

    var spaceSelection: SwitcherSession<String>? {
        guard case let .spaces(selection, _) = self else {
            return nil
        }
        return selection
    }

    var description: String {
        switch self {
        case let .windows(selection, _):
            "windows selected=\(selection.selectedIndex)"
        case let .spaces(selection, _):
            "spaces selected=\(selection.selectedIndex)"
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

    mutating func stepSpace(_ direction: SwitcherDirection) -> Bool {
        guard case let .spaces(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        selection.step(direction)
        self = .spaces(selection: selection, anchorFrame: anchorFrame)
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

    mutating func selectSpace(_ spaceID: String) -> Bool {
        guard case let .spaces(currentSelection, anchorFrame) = self else {
            return false
        }
        var selection = currentSelection
        guard selection.select(spaceID) else {
            return false
        }
        self = .spaces(selection: selection, anchorFrame: anchorFrame)
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

    mutating func reconcileSpaces(_ spaceIDs: [String], anchorFrame: WindowFrame?) -> Bool {
        guard case let .spaces(currentSelection, _) = self else {
            return false
        }
        var selection = currentSelection
        guard selection.reconcile(with: spaceIDs) else {
            return false
        }
        self = .spaces(selection: selection, anchorFrame: anchorFrame)
        return true
    }
}
