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
        let frontToBackIndex = CGWindowStackOrder.frontToBackIndexByWindowID()
        return handles.map(axClient.snapshot).sorted {
            Self.sortByFrontToBackOrder($0, $1, frontToBackIndex: frontToBackIndex)
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

    private static func sortByFrontToBackOrder(
        _ lhs: WindowSnapshot,
        _ rhs: WindowSnapshot,
        frontToBackIndex: [WindowID: Int]
    ) -> Bool {
        switch (frontToBackIndex[lhs.id], frontToBackIndex[rhs.id]) {
        case let (lhsIndex?, rhsIndex?):
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            return lhs.id < rhs.id
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return fallbackWindowOrder(lhs, rhs)
        }
    }

    private static func fallbackWindowOrder(_ lhs: WindowSnapshot, _ rhs: WindowSnapshot) -> Bool {
        if lhs.app.name == rhs.app.name {
            return lhs.id < rhs.id
        }
        return lhs.app.name.localizedCaseInsensitiveCompare(rhs.app.name) == .orderedAscending
    }
}

private enum CGWindowStackOrder {
    static func frontToBackIndexByWindowID() -> [WindowID: Int] {
        guard let rawList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var indexByID: [WindowID: Int] = [:]
        for (index, info) in rawList.enumerated() {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber
            else {
                continue
            }

            indexByID[WindowID(number.uint32Value)] = index
        }
        return indexByID
    }
}
