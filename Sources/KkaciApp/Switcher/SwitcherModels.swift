import AppKit
import KkaciCore

enum SwitcherDirection {
    case forward
    case backward
}

struct WindowSwitcherItem {
    let id: WindowID
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
    let name: String
    let windows: [WindowSwitcherItem]
    let preview: NSImage?
}
