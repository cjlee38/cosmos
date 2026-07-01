import CoreGraphics
import Foundation

public final class WindowRegistry: WindowSystem {
    private let axClient: AXClient
    private var handlesByID: [WindowID: WindowHandle] = [:]

    public init(axClient: AXClient) {
        self.axClient = axClient
    }

    @discardableResult
    public func refresh() -> [WindowSnapshot] {
        let handles = axClient.enumerateWindows()
        handlesByID = Dictionary(uniqueKeysWithValues: handles.map { ($0.id, $0) })
        return handles.map(axClient.snapshot).sorted { lhs, rhs in
            if lhs.app.name == rhs.app.name {
                return lhs.id < rhs.id
            }
            return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
        }
    }

    public func handle(for id: WindowID) -> WindowHandle? {
        handlesByID[id]
    }

    public func contains(_ id: WindowID) -> Bool {
        handlesByID[id] != nil
    }

    public func focusedWindowID() -> WindowID? {
        axClient.focusedWindowID()
    }

    public func snapshot(for id: WindowID) -> WindowSnapshot? {
        handle(for: id).map(axClient.snapshot)
    }

    public func frame(for id: WindowID) -> WindowFrame? {
        guard let handle = handle(for: id) else {
            return nil
        }
        return axClient.frame(for: handle.axWindow)
    }

    public func setPosition(_ point: CGPoint, for id: WindowID) throws {
        guard let handle = handle(for: id) else {
            throw WorkspaceError.windowNotFound(id)
        }
        try axClient.setPosition(point, for: handle.axWindow)
    }

    public func setFrame(_ frame: WindowFrame, for id: WindowID) throws {
        guard let handle = handle(for: id) else {
            throw WorkspaceError.windowNotFound(id)
        }
        try axClient.setFrame(frame, for: handle.axWindow)
    }

    public func focus(_ id: WindowID) {
        guard let handle = handle(for: id) else {
            return
        }
        axClient.focus(handle)
    }
}
