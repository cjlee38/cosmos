import Foundation

struct WindowSetDiff: Equatable {
    let removed: [WindowID]

    static let empty = WindowSetDiff(removed: [])
}

final class WindowStateCache {
    private(set) var windows: [WindowSnapshot] = []
    private(set) var focusedWindowID: WindowID?
    private(set) var displayTopology = DisplayTopologySnapshot.empty
    private var hasLoadedWindowSet = false

    func replace(
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        displayTopology: DisplayTopologySnapshot
    ) -> WindowSetDiff {
        let previousWindowIDs = Set(self.windows.map(\.id))
        let windowIDs = Set(windows.map(\.id))
        let diff = hasLoadedWindowSet
            ? WindowSetDiff(removed: previousWindowIDs.subtracting(windowIDs).sorted())
            : .empty

        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.displayTopology = displayTopology
        hasLoadedWindowSet = true
        return diff
    }

    func snapshot(for id: WindowID) -> WindowSnapshot? {
        windows.first { $0.id == id }
    }

    func updateDisplayTopology(_ displayTopology: DisplayTopologySnapshot) {
        self.displayTopology = displayTopology
    }

    func updateFrame(_ frame: WindowFrame, for id: WindowID) {
        guard let index = windows.firstIndex(where: { $0.id == id }) else {
            return
        }
        let window = windows[index]
        windows[index] = WindowSnapshot(
            id: window.id,
            app: window.app,
            title: window.title,
            frame: frame,
            isMinimized: window.isMinimized
        )
    }

    func updateFocusedWindowID(_ id: WindowID?) {
        focusedWindowID = id
    }
}
