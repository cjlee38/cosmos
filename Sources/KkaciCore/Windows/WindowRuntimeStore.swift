import Foundation

final class WindowRuntimeStore {
    private(set) var windows: [WindowSnapshot] = []
    private(set) var focusedWindowID: WindowID?
    private(set) var displayTopology = DisplayTopologySnapshot.empty

    var monitorSlots: [MonitorSlotSnapshot] {
        displayTopology.monitorSlots
    }

    func replace(
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        displayTopology: DisplayTopologySnapshot
    ) {
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.displayTopology = displayTopology
    }

    func snapshot(for id: WindowID) -> WindowSnapshot? {
        windows.first { $0.id == id }
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
