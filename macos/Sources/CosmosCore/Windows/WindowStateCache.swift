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

    func apply(
        _ discovery: WindowDiscoverySnapshot,
        displayTopology: DisplayTopologySnapshot
    ) -> WindowSetDiff {
        switch discovery.scope {
        case .full:
            let unresolvedWindows = windows.filter {
                discovery.unresolvedWindowIDs.contains($0.id)
            }
            return replace(
                windows: discovery.windows + unresolvedWindows,
                focusedWindowID: discovery.focusedWindowID,
                displayTopology: displayTopology
            )
        case .windows:
            var windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
            for window in discovery.windows {
                windowsByID[window.id] = window
            }

            var orderedWindows: [WindowSnapshot] = []
            var seen: Set<WindowID> = []
            for id in discovery.frontToBackWindowIDs {
                guard let window = windowsByID[id] else {
                    continue
                }
                orderedWindows.append(window)
                seen.insert(id)
            }
            orderedWindows.append(contentsOf: windows.filter { !seen.contains($0.id) }.compactMap {
                windowsByID[$0.id]
            })

            windows = orderedWindows
            focusedWindowID = discovery.focusedWindowID
            self.displayTopology = displayTopology
            return .empty
        }
    }

    func snapshot(for id: WindowID) -> WindowSnapshot? {
        windows.first { $0.id == id }
    }

    func updateDisplayTopology(_ displayTopology: DisplayTopologySnapshot) {
        self.displayTopology = displayTopology
    }

    func remove(_ windowIDs: Set<WindowID>) {
        guard !windowIDs.isEmpty else {
            return
        }
        windows.removeAll { windowIDs.contains($0.id) }
        if let focusedWindowID, windowIDs.contains(focusedWindowID) {
            self.focusedWindowID = nil
        }
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
