import Foundation

final class WindowRuntimeStore {
    private(set) var windows: [WindowSnapshot] = []
    private(set) var focusedWindowID: WindowID?
    private(set) var monitorSlots: [MonitorSlotSnapshot] = []

    func replace(
        windows: [WindowSnapshot],
        focusedWindowID: WindowID?,
        monitorSlots: [MonitorSlotSnapshot]
    ) {
        self.windows = windows
        self.focusedWindowID = focusedWindowID
        self.monitorSlots = monitorSlots
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
